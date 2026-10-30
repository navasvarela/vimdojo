// The API's routes. Dependencies come in as arguments, so tests can run the
// whole app against a real SQLite database and a stand-in for GitHub.
import { z } from "zod"
import {
  DAY_MS,
  HANDLE_CHANGE_INTERVAL_MS,
  HANDLE_HOLD_MS,
  MINUTE_MS,
  OAUTH_COOKIE_SECONDS,
  TOKEN_LIFETIME_MS,
  TOKEN_TOUCH_INTERVAL_MS,
} from "./config"
import { newToken, pkceChallenge, randomUrlSafe, sha256Hex } from "./crypto"
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
  withStandardHeaders,
} from "./http"
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

export type AppConfig = {
  readonly siteOrigin: string
  readonly apiOrigin: string
  readonly clientId: string
  readonly rateLimitSalt: string
}

export type App = {
  readonly store: Store
  readonly github: GitHub
  readonly config: AppConfig
  readonly now: () => number
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

function publicUser(user: UserRow): Record<string, unknown> {
  return { handle: user.handle, created_at: isoDate(user.created_at) }
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
async function ipSubject(request: Request, app: App): Promise<string> {
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown"
  const day = Math.floor(app.now() / DAY_MS)
  return `ip:${await sha256Hex(`${app.config.rateLimitSalt}:${day}:${ip}`)}`
}

async function limitByIp(request: Request, app: App, perMinute: number): Promise<void> {
  await enforceRate(app, await ipSubject(request, app), perMinute)
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
  await limitByIp(request, app, LOGIN_RATE_PER_MINUTE)
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
  await limitByIp(request, app, LOGIN_RATE_PER_MINUTE)
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
  await limitByIp(request, app, LOGIN_RATE_PER_MINUTE)
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
  await limitByIp(request, app, DEVICE_POLL_RATE_PER_MINUTE)
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
  const response = json({ ...publicUser(token.user), handle_rules: HANDLE_RULES })
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
  const changedAt = user.handle_changed_at
  if (user.handle !== null && changedAt !== null && now - changedAt < HANDLE_CHANGE_INTERVAL_MS) {
    throw new ApiError(
      Status.TooManyRequests,
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
    return json(publicUser(token.user))
  }
  await checkHandleFree(app, token.user, handle)
  const now = app.now()
  if (!(await app.store.setHandle(token.user, handle, now, now + HANDLE_HOLD_MS))) {
    throw new ApiError(Status.Conflict, "handle_taken", "That handle is taken.")
  }
  return json(publicUser({ ...token.user, handle }))
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

/** Everything stored about the account. Token hashes aren't personal data, and stay private. */
const exportMe: Handler = async (request, app) => {
  const { token } = await authenticate(request, app)
  const tokens = await app.store.tokensOf(token.user_id, app.now())
  return json({
    user: {
      github_id: token.user.github_id,
      handle: token.user.handle,
      handle_changed_at: isoDate(token.user.handle_changed_at),
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

const ROUTES: ReadonlyArray<readonly [string, RegExp, Handler]> = [
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

export async function handleRequest(request: Request, app: App): Promise<Response> {
  const { siteOrigin } = app.config
  if (request.method === "OPTIONS") {
    return withStandardHeaders(preflight(request, siteOrigin), request, siteOrigin)
  }
  try {
    return withStandardHeaders(await route(request, app), request, siteOrigin)
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
  await app.store.sweep(app.now(), app.now() - DAY_MS)
}
