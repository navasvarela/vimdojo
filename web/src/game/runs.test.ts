import { describe, expect, it } from "vitest"
import { RunError, RunsApi, verdictText, WEB_CLIENT, type Run, type WebRun } from "./runs"

type Route = { readonly status: number; readonly body?: unknown }

function apiWith(routes: Record<string, Route>): {
  api: RunsApi
  calls: Array<{ path: string; init: RequestInit | undefined }>
} {
  const calls: Array<{ path: string; init: RequestInit | undefined }> = []
  const fetcher: typeof fetch = async (input, init) => {
    const path = new URL(String(input)).pathname.replace("/api/v1", "")
    calls.push({ path, init })
    const route = routes[`${init?.method ?? "GET"} ${path}`]
    if (route === undefined) {
      throw new TypeError("network down")
    }
    return new Response(JSON.stringify(route.body ?? {}), { status: route.status })
  }
  return { api: new RunsApi(fetcher), calls }
}

const RUN: WebRun = {
  level_id: "basic-motions-01",
  level_hash: "sha256:abc",
  log: { keys: ["j", "j"], deltas_ms: [0, 120] },
  claimed: { keys: 2, seconds: 0.12, hinted: false },
}

function run(status: Run["status"], verified: number | null = null): Run {
  return {
    id: "r1",
    level_id: "basic-motions-01",
    status,
    claimed_keys: 5,
    verified_keys: verified,
  }
}

describe("submitting a web run", () => {
  it("sends the keys with the session cookie, marked as from the web", async () => {
    const { api, calls } = apiWith({
      "POST /runs": { status: 202, body: { id: "r1", status: "pending" } },
    })
    expect(await api.submit(RUN)).toEqual({ id: "r1", status: "pending" })
    const sent = calls[0]
    expect(sent?.init?.credentials).toBe("include")
    expect(JSON.parse(String(sent?.init?.body))).toEqual({
      level_id: "basic-motions-01",
      level_hash: "sha256:abc",
      nvim: WEB_CLIENT,
      keys: ["j", "j"],
      deltas_ms: [0, 120],
      claimed: { keys: 2, seconds: 0.12, hinted: false },
    })
  })

  it("passes on the server's reason when it refuses", async () => {
    const { api } = apiWith({
      "POST /runs": { status: 409, body: { message: "That level has changed since this run." } },
    })
    await expect(api.submit(RUN)).rejects.toThrow("That level has changed since this run.")
  })

  it("says to sign in again when the session has expired", async () => {
    const { api } = apiWith({ "POST /runs": { status: 401 } })
    await expect(api.submit(RUN)).rejects.toThrow(/sign in again/i)
  })

  it("says when the server can't be reached", async () => {
    const { api } = apiWith({})
    await expect(api.submit(RUN)).rejects.toBeInstanceOf(RunError)
  })
})

describe("whether the player is signed in", () => {
  it.each([
    [200, true],
    [401, false],
    [500, undefined],
  ] as const)("a %d means %s", async (status, expected) => {
    const { api } = apiWith({ "GET /me": { status, body: { handle: "ana", handle_rules: "" } } })
    expect(await api.signedIn()).toBe(expected)
  })

  it("is unknown when the server can't be reached", async () => {
    expect(await apiWith({}).api.signedIn()).toBeUndefined()
  })
})

describe("a verdict in words", () => {
  it("has none while the run is pending", () => {
    expect(verdictText(run("pending"))).toBeUndefined()
  })

  it.each([
    ["verified", 5, "Verified: 5 keys."],
    ["mismatch", 4, "Verified at 4 keys (the demo counted 5)."],
    ["not_best", null, "This run doesn't beat your verified best."],
  ] as const)("words %s", (status, verified, text) => {
    expect(verdictText(run(status, verified))).toBe(text)
  })

  it("blames the emulation when Neovim rejects a run", () => {
    expect(verdictText(run("rejected"))).toMatch(/emulation/)
  })
})
