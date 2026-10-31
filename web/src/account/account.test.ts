import { beforeEach, describe, expect, it, vi } from "vitest"
import { accountPolicy, injectPolicy } from "../../build/csp"
import { AccountApi, DELETE_PHRASE } from "./api"
import { AccountPage } from "./page"

type Route = { readonly status: number; readonly body?: unknown }

/** A stand-in for fetch: answers by "METHOD /path", and records what it was sent. */
function fakeServer(routes: Record<string, Route>) {
  const calls: Array<{ key: string; init: RequestInit | undefined }> = []
  const fetcher: typeof fetch = async (input, init) => {
    const path = new URL(String(input)).pathname.replace("/api/v1", "")
    const key = `${init?.method ?? "GET"} ${path}`
    calls.push({ key, init })
    const route = routes[key]
    if (route === undefined) {
      throw new TypeError("network down")
    }
    return new Response(route.body === undefined ? null : JSON.stringify(route.body), {
      status: route.status,
    })
  }
  return { calls, fetcher, routes }
}

const RULES = "3 to 20 characters"
const SIGNED_IN = { status: 200, body: { handle: "ana", handle_rules: RULES } }
const LOGINS = {
  status: 200,
  body: {
    tokens: [
      {
        id: "t1",
        kind: "web",
        created_at: "2026-10-01T00:00:00Z",
        last_used_at: "2026-10-30T00:00:00Z",
        current: true,
      },
      {
        id: "t2",
        kind: "plugin",
        created_at: "2026-10-02T00:00:00Z",
        last_used_at: "2026-10-03T00:00:00Z",
        current: false,
      },
    ],
  },
}

describe("account page", () => {
  let root: HTMLElement

  beforeEach(() => {
    root = document.createElement("div")
  })

  async function show(routes: Record<string, Route>, loginFailed = false) {
    const server = fakeServer(routes)
    await new AccountPage(root, new AccountApi(server.fetcher), loginFailed).show()
    return server
  }

  function button(text: string): HTMLButtonElement {
    const found = [...root.querySelectorAll("button")].find((b) => b.textContent === text)
    if (found === undefined) {
      throw new Error(`no button "${text}"`)
    }
    return found
  }

  it("offers sign-in when nobody is signed in", async () => {
    await show({ "GET /me": { status: 401, body: { message: "Sign in first." } } })
    expect(root.querySelector("a.primary")?.getAttribute("href")).toContain(
      "/api/v1/auth/github/start",
    )
  })

  it("says when signing in failed", async () => {
    await show({ "GET /me": { status: 401 } }, true)
    expect(root.textContent).toContain("didn't work")
  })

  it("asks a new player for a handle", async () => {
    await show({ "GET /me": { status: 200, body: { handle: null, handle_rules: RULES } } })
    expect(root.textContent).toContain("Pick a public handle")
    expect(root.textContent).toContain(RULES)
  })

  it("shows why the server refused a handle", async () => {
    const server = await show({
      "GET /me": { status: 200, body: { handle: null, handle_rules: RULES } },
      "PATCH /me": { status: 409, body: { message: "That handle is taken." } },
    })
    const input = root.querySelector<HTMLInputElement>("#handle")
    if (input === null) throw new Error("no input")
    input.value = "ana"
    root.querySelector("form")?.dispatchEvent(new Event("submit", { cancelable: true }))
    await vi.waitFor(() => expect(root.textContent).toContain("That handle is taken."))
    expect(server.calls.at(-1)?.init?.body).toBe('{"handle":"ana"}')
  })

  it("confirms a handle change, and says when the next one can happen", async () => {
    const server = await show({
      "GET /me": {
        status: 200,
        body: { handle: "ana", handle_rules: RULES, handle_changes_at: null },
      },
      "GET /me/tokens": { status: 200, body: { tokens: [] } },
      "PATCH /me": { status: 200, body: {} },
    })
    const input = root.querySelector<HTMLInputElement>("#handle")
    if (input === null) throw new Error("no input")
    input.value = "bea"
    server.routes["GET /me"] = {
      status: 200,
      body: { handle: "bea", handle_rules: RULES, handle_changes_at: "2026-11-30T12:00:00.000Z" },
    }
    root.querySelector("form")?.dispatchEvent(new Event("submit", { cancelable: true }))
    await vi.waitFor(() => expect(root.textContent).toContain("Your handle is now bea."))
    expect(root.textContent).toContain("change yours again on 2026-11-30")
    expect(root.querySelector("#handle")).toBeNull()
  })

  it("says until when a new handle can change freely", async () => {
    await show({
      "GET /me": {
        status: 200,
        body: { handle: "ana", handle_rules: RULES, handle_free_until: "2026-11-01T12:15:30.000Z" },
      },
      "GET /me/tokens": { status: 200, body: { tokens: [] } },
    })
    expect(root.textContent).toContain("freely until 2026-11-01 12:15 UTC")
    expect(root.querySelector("#handle")).not.toBeNull()
  })

  it("shows a failure next to the form that caused it, and lets the player retry", async () => {
    await show({
      "GET /me": {
        status: 200,
        body: { handle: "ana", handle_rules: RULES, handle_changes_at: null },
      },
      "GET /me/tokens": { status: 200, body: { tokens: [] } },
      "PATCH /me": { status: 409, body: { message: "That handle is taken." } },
    })
    const input = root.querySelector<HTMLInputElement>("#handle")
    const form = root.querySelector("form")
    if (input === null || form === null) throw new Error("no form")
    input.value = "bea"
    form.dispatchEvent(new Event("submit", { cancelable: true }))
    await vi.waitFor(() => expect(form.textContent).toContain("That handle is taken."))
    expect(form.querySelector("button")?.disabled).toBe(false)
    expect(input.value).toBe("bea")
  })

  it("disables a button while its request is running", async () => {
    let finish: (response: Response) => void = () => undefined
    const fetcher: typeof fetch = (input, init) => {
      const path = new URL(String(input)).pathname
      if (init?.method === "PATCH") {
        return new Promise((resolve) => {
          finish = resolve
        })
      }
      return Promise.resolve(
        new Response(
          JSON.stringify(
            path.endsWith("/tokens")
              ? { tokens: [] }
              : { handle: null, handle_rules: RULES, handle_changes_at: null },
          ),
        ),
      )
    }
    await new AccountPage(root, new AccountApi(fetcher), false).show()
    const form = root.querySelector("form")
    if (form === null) throw new Error("no form")
    form.dispatchEvent(new Event("submit", { cancelable: true }))
    expect(form.querySelector("button")?.disabled).toBe(true)
    finish(new Response(JSON.stringify({ message: "no" }), { status: 409 }))
    await vi.waitFor(() => expect(form.querySelector("button")?.disabled).toBe(false))
  })

  it("renders a handle as text, not HTML", async () => {
    await show({
      "GET /me": { status: 200, body: { handle: "<img src=x>", handle_rules: RULES } },
      "GET /me/tokens": { status: 200, body: { tokens: [] } },
    })
    expect(root.querySelector("img")).toBeNull()
    expect(root.textContent).toContain("<img src=x>")
  })

  it("lists logins, and only offers to revoke the others", async () => {
    const server = await show({
      "GET /me": SIGNED_IN,
      "GET /me/tokens": LOGINS,
      "DELETE /me/tokens/t2": { status: 204 },
    })
    expect(root.textContent).toContain("Browser, since 2026-10-01")
    expect(
      [...root.querySelectorAll("button")].filter((b) => b.textContent === "Revoke"),
    ).toHaveLength(1)
    button("Revoke").click()
    await vi.waitFor(() => expect(server.calls.map((c) => c.key)).toContain("DELETE /me/tokens/t2"))
  })

  it("keeps delete disabled until the phrase is typed", async () => {
    const server = await show({
      "GET /me": SIGNED_IN,
      "GET /me/tokens": LOGINS,
      "DELETE /me": { status: 204 },
    })
    const del = button("Delete my account")
    const input = root.querySelector<HTMLInputElement>("#confirm-delete")
    if (input === null) throw new Error("no input")
    expect(del.disabled).toBe(true)
    input.value = "delete"
    input.dispatchEvent(new Event("input"))
    expect(del.disabled).toBe(true)
    input.value = DELETE_PHRASE
    input.dispatchEvent(new Event("input"))
    expect(del.disabled).toBe(false)
    server.routes["GET /me"] = { status: 401 }
    del.form?.dispatchEvent(new Event("submit", { cancelable: true }))
    await vi.waitFor(() => expect(root.textContent).toContain("Sign in with GitHub"))
    expect(server.calls.find((c) => c.key === "DELETE /me")?.init?.body).toBe(
      JSON.stringify({ confirm: DELETE_PHRASE }),
    )
  })

  it("sends the session cookie on every call", async () => {
    const server = await show({ "GET /me": SIGNED_IN, "GET /me/tokens": LOGINS })
    expect(server.calls.every((c) => c.init?.credentials === "include")).toBe(true)
  })

  it("explains a network failure instead of breaking", async () => {
    await show({})
    expect(root.textContent).toContain("Couldn't reach the server")
  })
})

describe("account page policy", () => {
  it("allows scripts from the site, and talking only to the API", () => {
    const policy = accountPolicy("https://api.example")
    expect(policy).toContain("default-src 'none'")
    expect(policy).toContain("script-src 'self'")
    expect(policy).toContain("connect-src https://api.example")
    expect(policy).not.toContain("unsafe")
  })

  it("goes in the head", () => {
    expect(injectPolicy("<html><head></head></html>", "https://a")).toMatch(
      /<head>\s+<meta http-equiv="Content-Security-Policy"/,
    )
  })

  it("refuses a page with no head", () => {
    expect(() => injectPolicy("<html></html>", "https://a")).toThrow()
  })
})
