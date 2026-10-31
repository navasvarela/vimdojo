// The whole app against a real local D1 (wrangler's own, so the same engine as
// `wrangler dev`), with the real migrations and a stand-in for GitHub.
import { readdirSync, readFileSync } from "node:fs"
import { join } from "node:path"
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import { getPlatformProxy } from "wrangler"
import { type App, handleRequest, sweep } from "../src/app"
import { DAY_MS, TOKEN_LIFETIME_MS } from "../src/config"
import { sha256Hex } from "../src/crypto"
import type { DevicePoll, GitHub } from "../src/github"
import type { Env } from "../src/config"
import { ApiError, Status } from "../src/http"
import { Store } from "../src/store"

const SITE = "https://site.test"
const API = "https://api.test"
const MIGRATIONS = new URL("../migrations/", import.meta.url).pathname

type Harness = {
  readonly dispose: () => Promise<void>
  readonly db: D1Database
  readonly app: App
  readonly advance: (ms: number) => void
  /** What GitHub answers: who logs in, and how the device flow is going. */
  readonly gh: { userId: number; poll: DevicePoll; refuseCode: boolean; lastVerifier: string }
}

async function applyMigrations(db: D1Database): Promise<void> {
  for (const file of readdirSync(MIGRATIONS).sort()) {
    const sql = readFileSync(join(MIGRATIONS, file), "utf8").replace(/^\s*--.*$/gm, "")
    for (const statement of sql.split(";").filter((part) => part.trim() !== "")) {
      await db.prepare(statement).run()
    }
  }
}

async function harness(): Promise<Harness> {
  // persist: false gives each test its own empty database.
  const { env, dispose } = await getPlatformProxy<Env>({ persist: false })
  const db = env.DB
  await applyMigrations(db)
  let now = Date.UTC(2026, 9, 30)
  const gh: Harness["gh"] = {
    userId: 1001,
    poll: { status: "pending", intervalSeconds: undefined },
    refuseCode: false,
    lastVerifier: "",
  }
  const github: GitHub = {
    startDevice: async () => ({
      deviceCode: "secret-device-code",
      userCode: "ABCD-1234",
      verificationUri: "https://github.com/login/device",
      expiresInSeconds: 900,
      intervalSeconds: 5,
    }),
    pollDevice: async () => gh.poll,
    exchangeCode: async (_code, verifier) => {
      if (gh.refuseCode) {
        throw new ApiError(Status.BadRequest, "login_failed", "no")
      }
      gh.lastVerifier = verifier
      return "gho_access"
    },
    userId: async () => gh.userId,
  }
  const app: App = {
    store: new Store(db),
    github,
    config: { siteOrigin: SITE, apiOrigin: API, clientId: "client", rateLimitSalt: "salt" },
    now: () => now,
  }
  return {
    dispose,
    db,
    app,
    gh,
    advance: (ms) => {
      now += ms
    },
  }
}

describe("the API", () => {
  let h: Harness

  beforeEach(async () => {
    h = await harness()
  })

  afterEach(async () => {
    await h.dispose()
  })

  type Options = {
    readonly token?: string
    readonly cookie?: string
    readonly origin?: string
    readonly body?: unknown
    readonly ip?: string
  }

  function call(method: string, path: string, options: Options = {}): Promise<Response> {
    const headers = new Headers()
    if (options.token !== undefined) headers.set("authorization", `Bearer ${options.token}`)
    if (options.cookie !== undefined) headers.set("cookie", options.cookie)
    if (options.origin !== undefined) headers.set("origin", options.origin)
    if (options.ip !== undefined) headers.set("cf-connecting-ip", options.ip)
    if (options.body !== undefined) headers.set("content-type", "application/json")
    return handleRequest(
      new Request(`${API}${path}`, {
        method,
        headers,
        ...(options.body === undefined ? {} : { body: JSON.stringify(options.body) }),
      }),
      h.app,
    )
  }

  /** Signs in through the device flow, as the plugin does. */
  async function pluginLogin(userId = 1001): Promise<string> {
    h.gh.userId = userId
    const start = await call("POST", "/api/v1/auth/device")
    const { device_id: deviceId } = (await start.json()) as { device_id: string }
    h.gh.poll = { status: "authorized", accessToken: "gho_access" }
    const poll = await call("POST", "/api/v1/auth/device/poll", { body: { device_id: deviceId } })
    return ((await poll.json()) as { token: string }).token
  }

  function cookiePair(response: Response, name: string): string | undefined {
    const cookie = response.headers.getSetCookie().find((c) => c.startsWith(`${name}=`))
    return cookie?.split(";")[0]
  }

  /** Moves time on with the tokens in use, so they don't expire on the way. */
  async function passDays(days: number, ...tokens: readonly string[]): Promise<void> {
    for (let day = 0; day < days; day += 7) {
      h.advance(Math.min(7, days - day) * DAY_MS)
      for (const token of tokens) {
        await call("GET", "/api/v1/me", { token })
      }
    }
  }

  /** Signs in through the browser flow and returns the session cookie. */
  async function browserLogin(userId = 1001): Promise<string> {
    h.gh.userId = userId
    const start = await call("GET", "/api/v1/auth/github/start")
    const oauth = cookiePair(start, "__Host-vdj_oauth") ?? ""
    const state = new URL(start.headers.get("location") ?? "").searchParams.get("state")
    const callback = await call("GET", `/api/v1/auth/github/callback?code=c&state=${state}`, {
      cookie: oauth,
    })
    return cookiePair(callback, "__Host-vdj_session") ?? ""
  }

  describe("device login", () => {
    it("never gives the plugin GitHub's device code", async () => {
      const response = await call("POST", "/api/v1/auth/device")
      const text = await response.text()
      expect(text).toContain("ABCD-1234")
      expect(text).not.toContain("secret-device-code")
    })

    it("stays pending until GitHub authorizes, then issues a token once", async () => {
      const start = await call("POST", "/api/v1/auth/device")
      const { device_id: id } = (await start.json()) as { device_id: string }
      const body = { device_id: id }

      const pending = await call("POST", "/api/v1/auth/device/poll", { body })
      expect(await pending.json()).toEqual({ status: "pending", interval: null })

      h.gh.poll = { status: "authorized", accessToken: "gho_access" }
      const done = await call("POST", "/api/v1/auth/device/poll", { body })
      const result = (await done.json()) as { status: string; token: string; handle: null }
      expect(result.status).toBe("ok")
      expect(result.token).toMatch(/^vdj_[\w-]{43}$/)
      expect(result.handle).toBeNull()

      const again = await call("POST", "/api/v1/auth/device/poll", { body })
      expect(await again.json()).toEqual({ status: "expired" })
    })

    it("reports a denied or expired login", async () => {
      const start = await call("POST", "/api/v1/auth/device")
      const body = (await start.json()) as { device_id: string }
      h.gh.poll = { status: "failed" }
      const poll = await call("POST", "/api/v1/auth/device/poll", {
        body: { device_id: body.device_id },
      })
      expect(await poll.json()).toEqual({ status: "expired" })
    })

    it("expires a login that takes too long", async () => {
      const start = await call("POST", "/api/v1/auth/device")
      const body = (await start.json()) as { device_id: string }
      h.advance(901_000)
      const poll = await call("POST", "/api/v1/auth/device/poll", {
        body: { device_id: body.device_id },
      })
      expect(await poll.json()).toEqual({ status: "expired" })
    })
  })

  describe("browser login", () => {
    it("redirects to GitHub with state and PKCE, and no scope", async () => {
      const response = await call("GET", "/api/v1/auth/github/start")
      const url = new URL(response.headers.get("location") ?? "")
      expect(url.origin).toBe("https://github.com")
      expect(url.searchParams.get("state")).toBeTruthy()
      expect(url.searchParams.get("code_challenge_method")).toBe("S256")
      expect(url.searchParams.get("redirect_uri")).toBe(`${API}/api/v1/auth/github/callback`)
      expect(url.searchParams.has("scope")).toBe(false)
      expect(cookiePair(response, "__Host-vdj_oauth")).toBeTruthy()
    })

    it("signs in with a secure, HttpOnly session cookie", async () => {
      const start = await call("GET", "/api/v1/auth/github/start")
      const oauth = cookiePair(start, "__Host-vdj_oauth") ?? ""
      const state = new URL(start.headers.get("location") ?? "").searchParams.get("state")
      const callback = await call("GET", `/api/v1/auth/github/callback?code=c&state=${state}`, {
        cookie: oauth,
      })
      expect(callback.headers.get("location")).toBe(`${SITE}/account/`)
      const cookies = callback.headers.getSetCookie()
      const session = cookies.find((c) => c.startsWith("__Host-vdj_session=")) ?? ""
      expect(session).toMatch(/HttpOnly; Secure; SameSite=Lax; Path=\//)
      expect(h.gh.lastVerifier).toBe(oauth.split("=")[1]?.split(".")[1])
      expect(cookies.some((c) => c.startsWith("__Host-vdj_oauth=;"))).toBe(true)
    })

    it.each([
      ["a state that doesn't match", "other", true],
      ["no login cookie", "any", false],
    ])("refuses a callback with %s", async (_name, state, sendCookie) => {
      const start = await call("GET", "/api/v1/auth/github/start")
      const oauth = cookiePair(start, "__Host-vdj_oauth") ?? ""
      const response = await call("GET", `/api/v1/auth/github/callback?code=c&state=${state}`, {
        ...(sendCookie ? { cookie: oauth } : {}),
      })
      expect(response.headers.get("location")).toBe(`${SITE}/account/?login=failed`)
      expect(cookiePair(response, "__Host-vdj_session")).toBeUndefined()
    })

    it("sends the player back when GitHub refuses the code", async () => {
      h.gh.refuseCode = true
      expect(await browserLogin()).toBe("")
    })

    it("recognises a returning player", async () => {
      await pluginLogin(1001)
      const token = await pluginLogin(1001)
      await call("PATCH", "/api/v1/me", { token, body: { handle: "ana" } })
      const again = await browserLogin(1001)
      const me = await call("GET", "/api/v1/me", { cookie: again })
      expect(((await me.json()) as { handle: string }).handle).toBe("ana")
    })
  })

  describe("tokens", () => {
    it("stores only the hash", async () => {
      const token = await pluginLogin()
      const row = await h.db
        .prepare("SELECT token_hash FROM tokens")
        .first<{ token_hash: string }>()
      expect(row?.token_hash).toBe(await sha256Hex(token))
      expect(JSON.stringify(row)).not.toContain(token)
    })

    it.each([
      ["no token", {}],
      ["a made-up token", { token: "vdj_nope" }],
      ["a made-up cookie", { cookie: "__Host-vdj_session=nope" }],
    ])("refuses %s", async (_name, options) => {
      const response = await call("GET", "/api/v1/me", options)
      expect(response.status).toBe(401)
    })

    it("doesn't accept a token in the query string", async () => {
      const token = await pluginLogin()
      const response = await call("GET", `/api/v1/me?token=${token}&access_token=${token}`)
      expect(response.status).toBe(401)
    })

    it("expires after 30 days unused, and slides while in use", async () => {
      const token = await pluginLogin()
      h.advance(TOKEN_LIFETIME_MS - DAY_MS)
      expect((await call("GET", "/api/v1/me", { token })).status).toBe(200)
      h.advance(TOKEN_LIFETIME_MS - DAY_MS)
      expect((await call("GET", "/api/v1/me", { token })).status).toBe(200)
      h.advance(TOKEN_LIFETIME_MS + 1)
      expect((await call("GET", "/api/v1/me", { token })).status).toBe(401)
    })

    it("revokes on logout", async () => {
      const token = await pluginLogin()
      expect((await call("POST", "/api/v1/auth/logout", { token })).status).toBe(204)
      expect((await call("GET", "/api/v1/me", { token })).status).toBe(401)
    })

    it("lists logins without their hashes, and revokes one by id", async () => {
      const first = await pluginLogin()
      const second = await pluginLogin()
      const list = await call("GET", "/api/v1/me/tokens", { token: first })
      const { tokens } = (await list.json()) as {
        tokens: Array<{ id: string; current: boolean; kind: string }>
      }
      expect(tokens).toHaveLength(2)
      expect(tokens.filter((t) => t.current)).toHaveLength(1)
      expect(JSON.stringify(tokens)).not.toMatch(/hash/)
      const other = tokens.find((t) => !t.current)
      const removed = await call("DELETE", `/api/v1/me/tokens/${other?.id}`, { token: first })
      expect(removed.status).toBe(204)
      expect((await call("GET", "/api/v1/me", { token: second })).status).toBe(401)
    })

    it("can't revoke another player's login", async () => {
      const mine = await pluginLogin(1)
      const theirs = await pluginLogin(2)
      const list = await call("GET", "/api/v1/me/tokens", { token: theirs })
      const { tokens } = (await list.json()) as { tokens: Array<{ id: string }> }
      const response = await call("DELETE", `/api/v1/me/tokens/${tokens[0]?.id}`, { token: mine })
      expect(response.status).toBe(404)
      expect((await call("GET", "/api/v1/me", { token: theirs })).status).toBe(200)
    })
  })

  describe("cross-site protection", () => {
    it("refuses a cookie write from another origin, or with no origin", async () => {
      const cookie = await browserLogin()
      for (const origin of ["https://evil.test", undefined]) {
        const response = await call("PATCH", "/api/v1/me", {
          cookie,
          body: { handle: "ana" },
          ...(origin === undefined ? {} : { origin }),
        })
        expect(response.status).toBe(403)
      }
    })

    it("allows a cookie write from the site", async () => {
      const cookie = await browserLogin()
      const response = await call("PATCH", "/api/v1/me", {
        cookie,
        origin: SITE,
        body: { handle: "ana" },
      })
      expect(response.status).toBe(200)
      expect(response.headers.get("access-control-allow-origin")).toBe(SITE)
      expect(response.headers.get("access-control-allow-credentials")).toBe("true")
    })

    it("needs a JSON content type, which a cross-site form can't send", async () => {
      const cookie = await browserLogin()
      const response = await handleRequest(
        new Request(`${API}/api/v1/me`, {
          method: "PATCH",
          headers: { cookie, origin: SITE, "content-type": "text/plain" },
          body: '{"handle":"ana"}',
        }),
        h.app,
      )
      expect(response.status).toBe(415)
    })

    it("gives other origins no CORS access", async () => {
      const token = await pluginLogin()
      const response = await call("GET", "/api/v1/me", { token, origin: "https://evil.test" })
      expect(response.headers.get("access-control-allow-origin")).toBeNull()
      const preflight = await call("OPTIONS", "/api/v1/me", { origin: "https://evil.test" })
      expect(preflight.headers.get("access-control-allow-methods")).toBeNull()
    })

    it("answers the site's preflight", async () => {
      const preflight = await call("OPTIONS", "/api/v1/me", { origin: SITE })
      expect(preflight.status).toBe(204)
      expect(preflight.headers.get("access-control-allow-methods")).toContain("DELETE")
      expect(preflight.headers.get("access-control-allow-origin")).toBe(SITE)
    })
  })

  describe("handles", () => {
    it("starts empty, so the board never shows a GitHub login by default", async () => {
      const token = await pluginLogin()
      const me = (await (await call("GET", "/api/v1/me", { token })).json()) as { handle: null }
      expect(me.handle).toBeNull()
    })

    it.each([
      ["ab", "handle_length"],
      ["a".repeat(21), "handle_length"],
      ["Ana", "handle_characters"],
      ["an a", "handle_characters"],
      ["<b>ana</b>", "handle_characters"],
      ["admin", "handle_reserved"],
      ["vimdojo", "handle_reserved"],
    ])("refuses %s", async (handle, code) => {
      const token = await pluginLogin()
      const response = await call("PATCH", "/api/v1/me", { token, body: { handle } })
      expect(response.status).toBe(422)
      expect(((await response.json()) as { error: string }).error).toBe(code)
    })

    it("keeps handles unique", async () => {
      const first = await pluginLogin(1)
      const second = await pluginLogin(2)
      await call("PATCH", "/api/v1/me", { token: first, body: { handle: "ana" } })
      const taken = await call("PATCH", "/api/v1/me", { token: second, body: { handle: "ana" } })
      expect(taken.status).toBe(409)
    })

    it("allows one change every 30 days, once the first day has passed", async () => {
      const token = await pluginLogin()
      expect((await call("PATCH", "/api/v1/me", { token, body: { handle: "ana" } })).status).toBe(
        200,
      )
      h.advance(DAY_MS)
      const soon = await call("PATCH", "/api/v1/me", { token, body: { handle: "bea" } })
      expect(soon.status).toBe(409)
      expect(((await soon.json()) as { error: string }).error).toBe("handle_cooldown")
      await passDays(29, token)
      expect((await call("PATCH", "/api/v1/me", { token, body: { handle: "bea" } })).status).toBe(
        200,
      )
    })

    it("says when a handle can next change, and until when it's free", async () => {
      const token = await pluginLogin()
      const timing = async (): Promise<unknown[]> => {
        const me = await call("GET", "/api/v1/me", { token })
        const body = (await me.json()) as { handle_changes_at: unknown; handle_free_until: unknown }
        return [body.handle_changes_at, body.handle_free_until]
      }
      const inDays = (days: number): string => new Date(h.app.now() + days * DAY_MS).toISOString()
      expect(await timing()).toEqual([null, null])
      await call("PATCH", "/api/v1/me", { token, body: { handle: "ana" } })
      expect(await timing()).toEqual([null, inDays(1)])
      h.advance(DAY_MS)
      expect(await timing()).toEqual([inDays(29), null])
      await passDays(29, token)
      expect(await timing()).toEqual([null, null])
    })

    it("lets a new handle change freely for its first day, and go back", async () => {
      const token = await pluginLogin()
      for (const handle of ["anna", "ana", "anna"]) {
        const response = await call("PATCH", "/api/v1/me", { token, body: { handle } })
        expect(response.status).toBe(200)
      }
    })

    it("doesn't restart the free day when the handle changes", async () => {
      const token = await pluginLogin()
      await call("PATCH", "/api/v1/me", { token, body: { handle: "ana" } })
      h.advance(DAY_MS - 1000)
      await call("PATCH", "/api/v1/me", { token, body: { handle: "bea" } })
      h.advance(2000)
      const late = await call("PATCH", "/api/v1/me", { token, body: { handle: "cyd" } })
      expect(late.status).toBe(409)
    })

    it("releases a handle abandoned in its first day to others", async () => {
      const first = await pluginLogin(1)
      const second = await pluginLogin(2)
      await call("PATCH", "/api/v1/me", { token: first, body: { handle: "ana" } })
      await call("PATCH", "/api/v1/me", { token: first, body: { handle: "bea" } })
      const free = await call("PATCH", "/api/v1/me", { token: second, body: { handle: "ana" } })
      expect(free.status).toBe(200)
    })

    it("backfills the window for handles picked before it existed", async () => {
      await h.db
        .prepare(
          "INSERT INTO users (id, github_id, handle, handle_changed_at, created_at) VALUES ('u', 9, 'old', 123, 1)",
        )
        .run()
      await h.db.prepare("INSERT INTO users (id, github_id, created_at) VALUES ('v', 10, 1)").run()
      const migration = readFileSync(join(MIGRATIONS, "0002_handle_window.sql"), "utf8")
      const backfill = migration.split(";").find((part) => part.includes("UPDATE users"))
      await h.db.prepare(backfill ?? "").run()
      const { results } = await h.db
        .prepare("SELECT handle_first_set_at AS at FROM users ORDER BY id")
        .all<{ at: number | null }>()
      expect(results.map((row) => row.at)).toEqual([123, null])
    })

    it("holds a released handle for 90 days", async () => {
      const first = await pluginLogin(1)
      const second = await pluginLogin(2)
      await call("PATCH", "/api/v1/me", { token: first, body: { handle: "ana" } })
      await passDays(30, first, second)
      await call("PATCH", "/api/v1/me", { token: first, body: { handle: "bea" } })
      const held = await call("PATCH", "/api/v1/me", { token: second, body: { handle: "ana" } })
      expect(held.status).toBe(409)
      await passDays(90, second)
      const free = await call("PATCH", "/api/v1/me", { token: second, body: { handle: "ana" } })
      expect(free.status).toBe(200)
    })
  })

  describe("the player's data", () => {
    it("exports what is stored, without token hashes", async () => {
      const token = await pluginLogin(4242)
      await call("PATCH", "/api/v1/me", { token, body: { handle: "ana" } })
      const text = await (await call("GET", "/api/v1/me/export", { token })).text()
      const data = JSON.parse(text) as { user: Record<string, unknown>; logins: unknown[] }
      expect(data.user["github_id"]).toBe(4242)
      expect(data.user["handle"]).toBe("ana")
      expect(data.logins).toHaveLength(1)
      expect(text).not.toContain(await sha256Hex(token))
    })

    it("needs the explicit phrase to delete", async () => {
      const token = await pluginLogin()
      const response = await call("DELETE", "/api/v1/me", { token, body: { confirm: "yes" } })
      expect(response.status).toBe(422)
      expect((await call("GET", "/api/v1/me", { token })).status).toBe(200)
    })

    it("deletes the account and every token, and holds the handle unlinked", async () => {
      const token = await pluginLogin(4242)
      await pluginLogin(4242)
      await call("PATCH", "/api/v1/me", { token, body: { handle: "ana" } })
      const response = await call("DELETE", "/api/v1/me", {
        token,
        body: { confirm: "delete my account" },
      })
      expect(response.status).toBe(204)
      expect((await call("GET", "/api/v1/me", { token })).status).toBe(401)
      const count = async (table: string): Promise<unknown> =>
        (await h.db.prepare(`SELECT count(*) AS n FROM ${table}`).first<{ n: number }>())?.n
      expect(await count("users")).toBe(0)
      expect(await count("tokens")).toBe(0)

      const newcomer = await pluginLogin(5)
      const held = await call("PATCH", "/api/v1/me", { token: newcomer, body: { handle: "ana" } })
      expect(held.status).toBe(409)
    })

    it("treats the same GitHub account as new after deletion", async () => {
      const token = await pluginLogin(4242)
      await call("DELETE", "/api/v1/me", { token, body: { confirm: "delete my account" } })
      const again = await pluginLogin(4242)
      const me = (await (await call("GET", "/api/v1/me", { token: again })).json()) as {
        handle: null
      }
      expect(me.handle).toBeNull()
    })
  })

  describe("rate limits and housekeeping", () => {
    it("limits logins per address, by hash only", async () => {
      for (let i = 0; i < 10; i++) {
        expect((await call("POST", "/api/v1/auth/device", { ip: "203.0.113.9" })).status).toBe(200)
      }
      expect((await call("POST", "/api/v1/auth/device", { ip: "203.0.113.9" })).status).toBe(429)
      expect((await call("POST", "/api/v1/auth/device", { ip: "203.0.113.10" })).status).toBe(200)
      const { results } = await h.db.prepare("SELECT subject FROM rate_limits").all()
      expect(JSON.stringify(results)).not.toContain("203.0.113")
    })

    it("doesn't let a login's polling use up the limit on starting one", async () => {
      const start = await call("POST", "/api/v1/auth/device", { ip: "203.0.113.9" })
      const { device_id: id } = (await start.json()) as { device_id: string }
      for (let poll = 0; poll < 12; poll++) {
        const response = await call("POST", "/api/v1/auth/device/poll", {
          ip: "203.0.113.9",
          body: { device_id: id },
        })
        expect(response.status).toBe(200)
      }
      expect((await call("POST", "/api/v1/auth/device", { ip: "203.0.113.9" })).status).toBe(200)
    })

    it("lets the limit recover in the next window", async () => {
      for (let i = 0; i < 11; i++) {
        await call("POST", "/api/v1/auth/device", { ip: "203.0.113.9" })
      }
      h.advance(60_000)
      expect((await call("POST", "/api/v1/auth/device", { ip: "203.0.113.9" })).status).toBe(200)
    })

    it("sweeps what has expired, and nothing else", async () => {
      const stale = await pluginLogin(1)
      await call("POST", "/api/v1/auth/device")
      h.advance(TOKEN_LIFETIME_MS + 1)
      const fresh = await pluginLogin(2)
      await sweep(h.app)
      const { results } = await h.db.prepare("SELECT token_hash FROM tokens").all<{
        token_hash: string
      }>()
      expect(results.map((r) => r.token_hash)).toEqual([await sha256Hex(fresh)])
      expect(await sha256Hex(stale)).not.toBe(results[0]?.token_hash)
    })
  })

  it("keeps internal errors out of the response", async () => {
    const broken: App = {
      ...h.app,
      github: {
        ...h.app.github,
        startDevice: () => Promise.reject(new Error("secret internals")),
      },
    }
    const response = await handleRequest(
      new Request(`${API}/api/v1/auth/device`, { method: "POST" }),
      broken,
    )
    expect(response.status).toBe(500)
    expect(await response.text()).not.toContain("secret internals")
  })

  it("sends security headers, and no-store on everything", async () => {
    const response = await call("GET", "/api/v1/nope")
    expect(response.status).toBe(404)
    expect(response.headers.get("strict-transport-security")).toContain("max-age=")
    expect(response.headers.get("cache-control")).toBe("no-store")
    expect(response.headers.get("x-content-type-options")).toBe("nosniff")
  })
})
