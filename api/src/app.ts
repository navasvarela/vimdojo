// The API's routes. Dependencies come in as arguments, so tests can run the
// whole app against a real SQLite database and a stand-in for GitHub.
import { z } from "zod"
import {
  DAY_MS,
  HANDLE_CHANGE_INTERVAL_MS,
  HANDLE_FREE_WINDOW_MS,
  HANDLE_HOLD_MS,
  MINUTE_MS,
  OAUTH_COOKIE_SECONDS,
  TOKEN_LIFETIME_MS,
  TOKEN_TOUCH_INTERVAL_MS,
} from "./config"
import { newToken, pkceChallenge, randomUrlSafe, sha256Hex } from "./crypto"
import { ownRank, ownScores, publicBoard, publicProfile } from "./boards"
import type { GitHub } from "./github"
import { HANDLE_RULES, handleProblem } from "./handles"
import {
  ApiError,
  cookieValue,
  errorResponse,
  hostCookie,
  json,
  noContent,
  parseBody,
  preflight,
  redirect,
  Status,
  withPublicHeaders,
  withStandardHeaders,
} from "./http"
import type { RunStore } from "./run-store"
import { publicRun, RunBody, submitRun } from "./runs"
import type { Store, TokenKind, TokenRow, TokenWithUser, UserRow } from "./store"

const SESSION_COOKIE = "__Host-vdj_session"
const OAUTH_COOKIE = "__Host-vdj_oauth"
const SESSION_COOKIE_SECONDS = TOKEN_LIFETIME_MS / 1000
const BEARER_PREFIX = "Bearer "
const LOGIN_RATE_PER_MINUTE = 10
// The plugin polls every 5 seconds by GitHub's default interval, so polling
// needs more room than other login routes.
const DEVICE_POLL_RATE_PER_MINUTE = 30
const ACCOUNT_RATE_PER_MINUTE = 60
const RUNS_PER_MINUTE = 30
const RUNS_PER_DAY = 1000

export type AppConfig = {
  readonly siteOrigin: string
  readonly apiOrigin: string
  readonly clientId: string
  readonly rateLimitSalt: string
}

export type App = {
  readonly store: Store
  readonly runs: RunStore
  readonly github: GitHub
  readonly config: AppConfig
  readonly now: () => number
  /** Starts verifying a player's runs in the background, after the response. */
  readonly verifySoon: (userId: string) => void
}

/** A signed-in request: who, with which token, and whether it came by cookie. */
type Auth = {
  readonly token: TokenWithUser
  /** The session cookie's value, when that is how the request signed in. */
  readonly sessionCookie: string | undefined
}

type Handler = (request: Request, app: App, params: readonly string[]) => Promise<Response>

function isoDate(ms: number | null): string | null {
  return ms === null ? null : new Date(ms).toISOString()
}

/** Until when a new handle can change freely; null once that window has passed. */
function handleFreeUntil(user: UserRow, now: number): number | null {
  if (user.handle_first_set_at === null) {
    return null
  }
  const until = user.handle_first_set_at + HANDLE_FREE_WINDOW_MS
  return now < until ? until : null
}

/** When the handle can next change; null when it can now, or before there is one. */
function handleChangesAt(user: UserRow, now: number): string | null {
  const next = (user.handle_changed_at ?? 0) + HANDLE_CHANGE_INTERVAL_MS
  const waiting = user.handle !== null && now < next && handleFreeUntil(user, now) === null
  return waiting ? isoDate(next) : null
}

function publicUser(user: UserRow, now: number): Record<string, unknown> {
  return {
    handle: user.handle,
    created_at: isoDate(user.created_at),
    handle_changes_at: handleChangesAt(user, now),
    handle_free_until: isoDate(handleFreeUntil(user, now)),
  }
}

function publicToken(token: TokenRow, currentId: string): Record<string, unknown> {
  return {
    id: token.id,
    kind: token.kind,
    created_at: isoDate(token.created_at),
    last_used_at: isoDate(token.last_used_at),
    current: token.id === currentId,
  }
}

async function enforceRate(app: App, subject: string, perMinute: number): Promise<void> {
  const windowStart = Math.floor(app.now() / MINUTE_MS) * MINUTE_MS
  if ((await app.store.countRequest(subject, windowStart)) > perMinute) {
    throw new ApiError(Status.TooManyRequests, "rate_limited", "Too many requests. Slow down.")
  }
}

/** The address is only ever stored as a hash with a salt that changes daily. */
async function ipHash(request: Request, app: App): Promise<string> {
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown"
  const day = Math.floor(app.now() / DAY_MS)
  return sha256Hex(`${app.config.rateLimitSalt}:${day}:${ip}`)
}

/** Polling counts apart from starting a login: one login polls 12 times a minute. */
type IpLimit = { readonly scope: "login" | "poll"; readonly perMinute: number }
const LOGIN_LIMIT: IpLimit = { scope: "login", perMinute: LOGIN_RATE_PER_MINUTE }
const POLL_LIMIT: IpLimit = { scope: "poll", perMinute: DEVICE_POLL_RATE_PER_MINUTE }

async function limitByIp(request: Request, app: App, limit: IpLimit): Promise<void> {
  await enforceRate(app, `${limit.scope}:${await ipHash(request, app)}`, limit.perMinute)
}

async function issueToken(app: App, userId: string, kind: TokenKind): Promise<string> {
  const token = newToken()
  const now = app.now()
  await app.store.insertToken({
    userId,
    tokenHash: await sha256Hex(token),
    kind,
    now,
    expiresAt: now + TOKEN_LIFETIME_MS,
  })
  return token
}

/** Cookie sessions can only write from the site itself; bearer tokens aren't sent by browsers. */
function checkOrigin(request: Request, auth: Auth, app: App): void {
  if (
    auth.sessionCookie !== undefined &&
    request.method !== "GET" &&
    request.headers.get("origin") !== app.config.siteOrigin
  ) {
    throw new ApiError(Status.Forbidden, "bad_origin", "This origin can't change your account.")
  }
}

function presentedToken(request: Request): { value: string; viaCookie: boolean } | undefined {
  const header = request.headers.get("authorization")
  if (header?.startsWith(BEARER_PREFIX)) {
    return { value: header.slice(BEARER_PREFIX.length), viaCookie: false }
  }
  const cookie = cookieValue(request, SESSION_COOKIE)
  return cookie === undefined ? undefined : { value: cookie, viaCookie: true }
}

async function authenticate(request: Request, app: App): Promise<Auth> {
  const presented = presentedToken(request)
  const now = app.now()
  const token = presented && (await app.store.tokenByHash(await sha256Hex(presented.value), now))
  if (!presented || !token) {
    throw new ApiError(Status.Unauthorized, "unauthenticated", "Sign in first.")
  }
  const auth = {
    token,
    sessionCookie: presented.viaCookie ? presented.value : undefined,
  }
  checkOrigin(request, auth, app)
  await enforceRate(app, `user:${token.user_id}`, ACCOUNT_RATE_PER_MINUTE)
  if (now - token.last_used_at > TOKEN_TOUCH_INTERVAL_MS) {
    await app.store.touchToken(token.id, now, now + TOKEN_LIFETIME_MS)
  }
  return auth
}

const callbackUrl = (app: App): string => `${app.config.apiOrigin}/api/v1/auth/github/callback`
const accountUrl = (app: App, query = ""): string => `${app.config.siteOrigin}/account/${query}`

const githubStart: Handler = async (request, app) => {
  await limitByIp(request, app, LOGIN_LIMIT)
  const state = randomUrlSafe()
  const verifier = randomUrlSafe()
  const url = new URL("https://github.com/login/oauth/authorize")
  url.searchParams.set("client_id", app.config.clientId)
  url.searchParams.set("redirect_uri", callbackUrl(app))
  url.searchParams.set("state", state)
  url.searchParams.set("code_challenge", await pkceChallenge(verifier))
  url.searchParams.set("code_challenge_method", "S256")
  const response = redirect(url.toString())
  response.headers.append(
    "set-cookie",
    hostCookie(OAUTH_COOKIE, `${state}.${verifier}`, OAUTH_COOKIE_SECONDS),
  )
  return response
}

const githubCallback: Handler = async (request, app) => {
  await limitByIp(request, app, LOGIN_LIMIT)
  const url = new URL(request.url)
  const code = url.searchParams.get("code")
  const [state, verifier] = (cookieValue(request, OAUTH_COOKIE) ?? "").split(".")
  const failure = (): Response => {
    const response = redirect(accountUrl(app, "?login=failed"))
    response.headers.append("set-cookie", hostCookie(OAUTH_COOKIE, "", 0))
    return response
  }
  // The state ties this callback to the browser that started the login.
  if (!code || !state || !verifier || url.searchParams.get("state") !== state) {
    return failure()
  }
  let githubId: number
  try {
    githubId = await app.github.userId(
      await app.github.exchangeCode(code, verifier, callbackUrl(app)),
    )
  } catch (error) {
    if (error instanceof ApiError) {
      return failure()
    }
    throw error
  }
  const user = await app.store.userForGitHub(githubId, app.now())
  const response = redirect(accountUrl(app))
  response.headers.append("set-cookie", hostCookie(OAUTH_COOKIE, "", 0))
  response.headers.append(
    "set-cookie",
    hostCookie(SESSION_COOKIE, await issueToken(app, user.id, "web"), SESSION_COOKIE_SECONDS),
  )
  return response
}

const deviceStart: Handler = async (request, app) => {
  await limitByIp(request, app, LOGIN_LIMIT)
  const device = await app.github.startDevice()
  const id = await app.store.insertDeviceLogin(
    device.deviceCode,
    app.now() + device.expiresInSeconds * 1000,
  )
  // The plugin only ever holds this id; GitHub's device code stays here.
  return json({
    device_id: id,
    user_code: device.userCode,
    verification_uri: device.verificationUri,
    interval: device.intervalSeconds,
    expires_in: device.expiresInSeconds,
  })
}

const DevicePollBody = z.object({ device_id: z.string().min(1).max(64) })

const devicePoll: Handler = async (request, app) => {
  await limitByIp(request, app, POLL_LIMIT)
  const { device_id: id } = await parseBody(request, DevicePollBody)
  const deviceCode = await app.store.deviceCode(id, app.now())
  if (deviceCode === undefined) {
    return json({ status: "expired" })
  }
  const poll = await app.github.pollDevice(deviceCode)
  if (poll.status === "pending") {
    return json({ status: "pending", interval: poll.intervalSeconds ?? null })
  }
  await app.store.deleteDeviceLogin(id)
  if (poll.status === "failed") {
    return json({ status: "expired" })
  }
  const user = await app.store.userForGitHub(await app.github.userId(poll.accessToken), app.now())
  return json({
    status: "ok",
    token: await issueToken(app, user.id, "plugin"),
    handle: user.handle,
  })
}

const logout: Handler = async (request, app) => {
  const auth = await authenticate(request, app)
  await app.store.deleteToken(auth.token.user_id, auth.token.id)
  const response = noContent()
  response.headers.append("set-cookie", hostCookie(SESSION_COOKIE, "", 0))
  return response
}

/** The site calls this on every visit, which keeps the session cookie sliding too. */
const getMe: Handler = async (request, app) => {
  const { token, sessionCookie } = await authenticate(request, app)
  const response = json({ ...publicUser(token.user, app.now()), handle_rules: HANDLE_RULES })
  if (sessionCookie !== undefined) {
    response.headers.append(
      "set-cookie",
      hostCookie(SESSION_COOKIE, sessionCookie, SESSION_COOKIE_SECONDS),
    )
  }
  return response
}

const PatchMeBody = z.object({ handle: z.string().max(64) })

async function checkHandleFree(app: App, user: UserRow, handle: string): Promise<void> {
  const problem = handleProblem(handle)
  if (problem !== undefined) {
    throw new ApiError(Status.UnprocessableEntity, `handle_${problem}`, `Use ${HANDLE_RULES}.`)
  }
  const now = app.now()
  if (handleChangesAt(user, now) !== null) {
    // A conflict with the account's state, not a rate limit: retrying soon can't help.
    throw new ApiError(
      Status.Conflict,
      "handle_cooldown",
      "A handle can only change once every 30 days.",
    )
  }
  if (await app.store.isHandleHeld(handle, now)) {
    throw new ApiError(Status.Conflict, "handle_taken", "That handle is taken.")
  }
}

const patchMe: Handler = async (request, app) => {
  const { token } = await authenticate(request, app)
  const { handle } = await parseBody(request, PatchMeBody)
  if (handle === token.user.handle) {
    return json(publicUser(token.user, app.now()))
  }
  await checkHandleFree(app, token.user, handle)
  const now = app.now()
  // A handle under a day old has no reputation to impersonate, and holding it
  // would stop a player going back after a mistaken rename.
  const heldUntil = handleFreeUntil(token.user, now) === null ? now + HANDLE_HOLD_MS : undefined
  if (!(await app.store.setHandle(token.user, handle, now, heldUntil))) {
    throw new ApiError(Status.Conflict, "handle_taken", "That handle is taken.")
  }
  return json(
    publicUser(
      {
        ...token.user,
        handle,
        handle_changed_at: now,
        handle_first_set_at: token.user.handle_first_set_at ?? now,
      },
      now,
    ),
  )
}

const getTokens: Handler = async (request, app) => {
  const { token } = await authenticate(request, app)
  const tokens = await app.store.tokensOf(token.user_id, app.now())
  return json({ tokens: tokens.map((row) => publicToken(row, token.id)) })
}

const deleteToken: Handler = async (request, app, [tokenId]) => {
  const { token } = await authenticate(request, app)
  if (tokenId === undefined || !(await app.store.deleteToken(token.user_id, tokenId))) {
    throw new ApiError(Status.NotFound, "not_found", "No such login.")
  }
  return noContent()
}

function parseStoredJson(text: string): unknown {
  return JSON.parse(text)
}

/** Everything stored about the account. Token hashes aren't personal data, and stay private. */
const exportMe: Handler = async (request, app) => {
  const { token } = await authenticate(request, app)
  const tokens = await app.store.tokensOf(token.user_id, app.now())
  const [runs, bests] = await Promise.all([
    app.runs.runsOf(token.user_id),
    app.runs.bestsOf(token.user_id),
  ])
  return json({
    runs: runs.map((run) => ({
      ...publicRun(run),
      level_hash: run.level_hash,
      keys: parseStoredJson(run.keys),
      deltas_ms: parseStoredJson(run.deltas_ms),
      nvim: run.nvim,
      claimed_seconds: run.claimed_seconds,
      hinted: run.hinted === 1,
      expires_at: isoDate(run.expires_at),
    })),
    bests: bests.map((best) => ({
      ...best,
      hinted: best.hinted === 1,
      first_at: isoDate(best.first_at),
    })),
    user: {
      github_id: token.user.github_id,
      handle: token.user.handle,
      handle_changed_at: isoDate(token.user.handle_changed_at),
      handle_first_set_at: isoDate(token.user.handle_first_set_at),
      created_at: isoDate(token.user.created_at),
    },
    logins: tokens.map((row) => ({
      kind: row.kind,
      created_at: isoDate(row.created_at),
      last_used_at: isoDate(row.last_used_at),
      expires_at: isoDate(row.expires_at),
    })),
  })
}

// Deleting is permanent, so the request has to say so on purpose.
const DeleteMeBody = z.object({ confirm: z.literal("delete my account") })

const deleteMe: Handler = async (request, app) => {
  const { token } = await authenticate(request, app)
  await parseBody(request, DeleteMeBody)
  await app.store.deleteUser(token.user, app.now() + HANDLE_HOLD_MS)
  const response = noContent()
  response.headers.append("set-cookie", hostCookie(SESSION_COOKIE, "", 0))
  return response
}

const postRun: Handler = async (request, app) => {
  const { token } = await authenticate(request, app)
  await enforceRate(app, `runs:${token.user_id}`, RUNS_PER_MINUTE)
  const today = Math.floor(app.now() / DAY_MS) * DAY_MS
  if ((await app.store.countRequest(`runs-day:${token.user_id}`, today)) > RUNS_PER_DAY) {
    throw new ApiError(Status.TooManyRequests, "rate_limited", "That's enough runs for today.")
  }
  const body = await parseBody(request, RunBody)
  const result = await submitRun(app.runs, token.user_id, body, app.now())
  if (result.isNew && result.status === "pending") {
    app.verifySoon(token.user_id)
  }
  return json({ id: result.id, status: result.status }, result.isNew ? Status.Accepted : Status.Ok)
}

const getRun: Handler = async (request, app, [runId]) => {
  const { token } = await authenticate(request, app)
  const run = runId === undefined ? undefined : await app.runs.runOf(token.user_id, runId)
  if (run === undefined) {
    throw new ApiError(Status.NotFound, "not_found", "No such run.")
  }
  return json(publicRun(run))
}

const getBoard: Handler = async (_request, app, [levelId]) =>
  json(await publicBoard(app.runs, levelId ?? ""))

const getOwnRank: Handler = async (request, app, [levelId]) => {
  const { token } = await authenticate(request, app)
  return json(await ownRank(app.runs, token.user_id, levelId ?? ""))
}

const getOwnScores: Handler = async (request, app) => {
  const { token } = await authenticate(request, app)
  return json(await ownScores(app.runs, token.user_id))
}

const getPlayer: Handler = async (_request, app, [handle]) =>
  json(await publicProfile(app.runs, handle ?? ""))

// Boards and profiles are the same for everyone, so they carry no cookies, can be
// cached, and can be read from anywhere.
const PUBLIC_ROUTES: ReadonlyArray<readonly [RegExp, Handler]> = [
  [/^\/api\/v1\/levels\/([\w-]+)\/board$/, getBoard],
  [/^\/api\/v1\/players\/([\w-]+)$/, getPlayer],
]

/** Whether a GET to this path is public, and so safe to cache for everyone. */
export function isPublicPath(pathname: string): boolean {
  return PUBLIC_ROUTES.some(([pattern]) => pattern.test(pathname))
}

const ROUTES: ReadonlyArray<readonly [string, RegExp, Handler]> = [
  ["GET", /^\/api\/v1\/levels\/([\w-]+)\/board\/me$/, getOwnRank],
  ["GET", /^\/api\/v1\/me\/scores$/, getOwnScores],
  ["GET", /^\/api\/v1\/auth\/github\/start$/, githubStart],
  ["GET", /^\/api\/v1\/auth\/github\/callback$/, githubCallback],
  ["POST", /^\/api\/v1\/auth\/device$/, deviceStart],
  ["POST", /^\/api\/v1\/auth\/device\/poll$/, devicePoll],
  ["POST", /^\/api\/v1\/auth\/logout$/, logout],
  ["GET", /^\/api\/v1\/me$/, getMe],
  ["PATCH", /^\/api\/v1\/me$/, patchMe],
  ["DELETE", /^\/api\/v1\/me$/, deleteMe],
  ["GET", /^\/api\/v1\/me\/export$/, exportMe],
  ["GET", /^\/api\/v1\/me\/tokens$/, getTokens],
  ["DELETE", /^\/api\/v1\/me\/tokens\/([\w-]+)$/, deleteToken],
  ["POST", /^\/api\/v1\/runs$/, postRun],
  ["GET", /^\/api\/v1\/runs\/([\w-]+)$/, getRun],
]

async function route(request: Request, app: App): Promise<Response> {
  const { pathname } = new URL(request.url)
  for (const [method, pattern, handler] of ROUTES) {
    const match = request.method === method ? pattern.exec(pathname) : null
    if (match) {
      return handler(request, app, match.slice(1))
    }
  }
  throw new ApiError(Status.NotFound, "not_found", "No such route.")
}

async function routePublic(request: Request, app: App): Promise<Response | undefined> {
  if (request.method !== "GET") {
    return undefined
  }
  const { pathname } = new URL(request.url)
  for (const [pattern, handler] of PUBLIC_ROUTES) {
    const match = pattern.exec(pathname)
    if (match) {
      return withPublicHeaders(await handler(request, app, match.slice(1)))
    }
  }
  return undefined
}

export async function handleRequest(request: Request, app: App): Promise<Response> {
  const { siteOrigin } = app.config
  if (request.method === "OPTIONS") {
    return withStandardHeaders(preflight(request, siteOrigin), request, siteOrigin)
  }
  try {
    return (
      (await routePublic(request, app)) ??
      withStandardHeaders(await route(request, app), request, siteOrigin)
    )
  } catch (error) {
    if (error instanceof ApiError) {
      return withStandardHeaders(errorResponse(error), request, siteOrigin)
    }
    // Details go to the Worker's logs, never to the client.
    console.error(
      "unhandled error:",
      error instanceof Error ? (error.stack ?? error.message) : error,
    )
    const internal = new ApiError(Status.InternalServerError, "internal", "Something went wrong.")
    return withStandardHeaders(errorResponse(internal), request, siteOrigin)
  }
}

/** Daily cleanup: expired logins, handle holds and rate-limit counters. */
export async function sweep(app: App): Promise<void> {
  // Yesterday's window can still be counting daily limits, so keep two days.
  await app.store.sweep(app.now(), app.now() - 2 * DAY_MS)
  await app.runs.sweep(app.now())
}
