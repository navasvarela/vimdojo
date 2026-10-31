import { beforeEach, describe, expect, it } from "vitest"
import { renderLevelOptions } from "../../build/board-levels"
import { parsePacks } from "../challenges"
import { BoardsApi } from "./api"
import { boardUrl, playerUrl, showBoard, showPlayer } from "./pages"

type Route = { readonly status: number; readonly body?: unknown }

function apiWith(routes: Record<string, Route>): {
  api: BoardsApi
  calls: Array<RequestInit | undefined>
} {
  const calls: Array<RequestInit | undefined> = []
  const fetcher: typeof fetch = async (input, init) => {
    calls.push(init)
    const route = routes[new URL(String(input)).pathname.replace("/api/v1", "")]
    if (route === undefined) {
      throw new TypeError("network down")
    }
    return new Response(JSON.stringify(route.body ?? {}), { status: route.status })
  }
  return { api: new BoardsApi(fetcher), calls }
}

const ENTRY = { rank: 1, handle: "ana", keys: 4, hinted: false, since: "2026-10-31" }

describe("the board page", () => {
  let root: HTMLElement

  beforeEach(() => {
    root = document.createElement("div")
  })

  it("lists players, linking to their profiles", async () => {
    const { api } = apiWith({
      "/levels/l/board": { status: 200, body: { entries: [ENTRY] } },
      "/levels/l/board/me": { status: 401 },
    })
    await showBoard(root, api, "l")
    expect(root.textContent).toContain("ana")
    expect(root.querySelector("tbody a")?.getAttribute("href")).toBe("/player/?handle=ana")
    expect(root.textContent).not.toContain("You're")
  })

  it("marks your line, and says your place when you're signed in", async () => {
    const { api } = apiWith({
      "/levels/l/board": { status: 200, body: { entries: [ENTRY] } },
      "/levels/l/board/me": { status: 200, body: { rank: 1, keys: 4 } },
    })
    await showBoard(root, api, "l")
    expect(root.querySelector(".board-mine")?.textContent).toContain("ana")
    expect(root.textContent).toContain("You're #1")
  })

  it("only sends the cookie when asking for your own place", async () => {
    const { api, calls } = apiWith({
      "/levels/l/board": { status: 200, body: { entries: [] } },
      "/levels/l/board/me": { status: 401 },
    })
    await showBoard(root, api, "l")
    expect(calls.map((init) => init?.credentials)).toEqual([undefined, "include"])
  })

  it("still shows the board when your place can't be loaded", async () => {
    const { api } = apiWith({ "/levels/l/board": { status: 200, body: { entries: [ENTRY] } } })
    await showBoard(root, api, "l")
    expect(root.textContent).toContain("ana")
  })

  it("says so when a board is empty", async () => {
    const { api } = apiWith({
      "/levels/l/board": { status: 200, body: { entries: [] } },
      "/levels/l/board/me": { status: 401 },
    })
    await showBoard(root, api, "l")
    expect(root.textContent).toContain("No verified runs yet")
  })

  it("explains a failure instead of breaking", async () => {
    const { api } = apiWith({})
    await showBoard(root, api, "l")
    expect(root.textContent).toContain("Couldn't load")
  })

  it("explains the mark only when someone used a hint", async () => {
    const { api } = apiWith({
      "/levels/l/board": { status: 200, body: { entries: [{ ...ENTRY, hinted: true }] } },
      "/levels/l/board/me": { status: 401 },
    })
    await showBoard(root, api, "l")
    expect(root.textContent).toContain("4*")
    expect(root.textContent).toContain("used the hint")
  })

  it("treats a hostile handle as text", async () => {
    const hostile = '<img src=x onerror="alert(1)">'
    const { api } = apiWith({
      "/levels/l/board": { status: 200, body: { entries: [{ ...ENTRY, handle: hostile }] } },
      "/levels/l/board/me": { status: 401 },
    })
    await showBoard(root, api, "l")
    expect(root.querySelector("img")).toBeNull()
    expect(root.textContent).toContain(hostile)
    expect(root.querySelector("tbody a")?.getAttribute("href")).toBe(playerUrl(hostile))
    expect(playerUrl(hostile)).not.toContain("<")
  })
})

describe("the profile page", () => {
  let root: HTMLElement
  let heading: HTMLElement

  beforeEach(() => {
    root = document.createElement("div")
    heading = document.createElement("h1")
  })

  const NAMES = new Map([["l", "Level title"]])

  it("shows verified bests by level name, linking to each board", async () => {
    const { api } = apiWith({
      "/players/ana": {
        status: 200,
        body: {
          handle: "ana",
          joined: "2026-10",
          bests: [{ level_id: "l", keys: 4, hinted: false, since: "2026-10-31" }],
        },
      },
    })
    await showPlayer(root, heading, api, "ana", NAMES)
    expect(heading.textContent).toBe("ana")
    expect(root.textContent).toContain("Level title")
    expect(root.textContent).toContain("Playing since 2026-10")
    expect(root.querySelector("tbody a")?.getAttribute("href")).toBe(boardUrl("l"))
  })

  it.each([
    ["an unknown handle", "nobody"],
    ["no handle", null],
  ])("says so for %s", async (_name, handle) => {
    const { api } = apiWith({ "/players/nobody": { status: 404 } })
    await showPlayer(root, heading, api, handle, NAMES)
    expect(root.textContent).toContain("No player has that handle")
  })

  it("encodes the handle it asks for", async () => {
    const { api, calls } = apiWith({})
    await showPlayer(root, heading, api, "a/../b", NAMES)
    expect(calls).toHaveLength(1)
    expect(root.textContent).toContain("Couldn't load")
  })
})

describe("the level picker", () => {
  const level = (id: string, title: string) => ({
    id,
    title,
    description: "d",
    start_text: ["a"],
    cursor_start: [1, 0],
    goal: { type: "cursor_at", line: 1, col: 0 },
    par_keys: 1,
    par_seconds: 1,
    hint: "h",
    solution: "l",
    teaches: ["l"],
  })

  it("lists ranked levels, not Setup ones, with their text escaped", () => {
    const html = renderLevelOptions(
      parsePacks([
        { pack: "a", title: "A & B", order: 1, levels: [level("one", "<One>")] },
        { pack: "s", title: "Setup", order: 2, track: "setup", levels: [level("two", "Two")] },
      ]),
    )
    expect(html).toContain('value="one"')
    expect(html).toContain("&lt;One&gt;")
    expect(html).toContain("A &amp; B")
    expect(html).not.toContain("two")
  })
})
