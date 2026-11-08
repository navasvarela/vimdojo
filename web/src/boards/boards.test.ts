import { beforeEach, describe, expect, it } from "vitest"
import { renderLevelOptions } from "../../build/board-levels"
import { parsePacks } from "../challenges"
import { BoardsApi } from "./api"
import {
  boardUrl,
  dailyUrl,
  overParText,
  playerUrl,
  showBoard,
  showDaily,
  showOverall,
  showPlayer,
} from "./pages"

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

describe("the overall board", () => {
  const OVERALL = { rank: 1, handle: "ana", solved: 12, over_par: 3 }

  it("lists players with their levels and keys over par", async () => {
    const root = document.createElement("div")
    const { api } = apiWith({
      "/overall": { status: 200, body: { entries: [OVERALL] } },
      "/overall/me": { status: 401 },
    })
    await showOverall(root, api)
    expect(root.querySelector("tbody")?.textContent).toBe("1ana12+3")
    expect(root.textContent).not.toContain("You're")
  })

  it("says your place when you're signed in", async () => {
    const root = document.createElement("div")
    const { api } = apiWith({
      "/overall": { status: 200, body: { entries: [OVERALL] } },
      "/overall/me": { status: 200, body: { rank: 1, solved: 12, over_par: 3 } },
    })
    await showOverall(root, api)
    expect(root.querySelector(".board-mine")?.textContent).toContain("ana")
    expect(root.textContent).toContain("You're #1, with 12 levels at +3 keys over par.")
  })

  it("says so when it can't load", async () => {
    const root = document.createElement("div")
    await showOverall(root, apiWith({}).api)
    expect(root.textContent).toContain("Couldn't load this")
  })

  it.each([
    [3, "+3"],
    [0, "0"],
    [-2, "−2"],
  ])("writes %i keys over par as %s", (overPar, text) => {
    expect(overParText(overPar)).toBe(text)
  })
})

describe("the daily board", () => {
  const NOW = Date.UTC(2026, 9, 31, 12)
  const NAMES = new Map([["l", "Basic motions"]])
  const DAILY_ENTRY = { rank: 1, handle: "ana", keys: 4, hinted: false }
  const today = { date: undefined, now: NOW, levelNames: NAMES }
  const body = (entries: readonly unknown[], date = "2026-10-31") => ({
    date,
    level_id: "l",
    entries,
  })
  let root: HTMLElement

  beforeEach(() => {
    root = document.createElement("div")
  })

  const links = (): Array<string | null> =>
    [...root.querySelectorAll("p.aside a")].map((link) => link.getAttribute("href"))

  it("names the day and its level, and lists players", async () => {
    const { api } = apiWith({
      "/daily": { status: 200, body: body([DAILY_ENTRY]) },
      "/daily/me": { status: 401 },
    })
    await showDaily(root, api, today)
    expect(root.textContent).toContain("2026-10-31: Basic motions")
    expect(root.textContent).toContain(":VimDojo daily")
    expect(root.querySelector("p a")?.getAttribute("href")).toBe("/#daily")
    expect(root.querySelector("tbody a")?.getAttribute("href")).toBe("/player/?handle=ana")
  })

  it("marks your line today, sending the cookie only for that", async () => {
    const { api, calls } = apiWith({
      "/daily": { status: 200, body: body([DAILY_ENTRY]) },
      "/daily/me": { status: 200, body: { rank: 1, keys: 4 } },
    })
    await showDaily(root, api, today)
    expect(root.querySelector(".board-mine")).not.toBeNull()
    expect(root.textContent).toContain("You're #1")
    expect(calls.filter((init) => init?.credentials === "include")).toHaveLength(1)
  })

  it("still shows the board if your place fails", async () => {
    const { api } = apiWith({ "/daily": { status: 200, body: body([DAILY_ENTRY]) } })
    await showDaily(root, api, today)
    expect(root.textContent).toContain("ana")
  })

  it("says so when nobody has played yet", async () => {
    const { api } = apiWith({ "/daily": { status: 200, body: body([]) } })
    await showDaily(root, api, today)
    expect(root.textContent).toContain("No verified runs yet")
  })

  it("links back from today, and not forward", async () => {
    const { api } = apiWith({ "/daily": { status: 200, body: body([]) } })
    await showDaily(root, api, today)
    expect(links()).toEqual([dailyUrl("2026-10-30")])
  })

  it("shows a past day without asking for your place, linking both ways", async () => {
    const { api, calls } = apiWith({
      "/daily/2026-10-01": { status: 200, body: body([DAILY_ENTRY], "2026-10-01") },
    })
    await showDaily(root, api, { ...today, date: "2026-10-01" })
    expect(calls).toHaveLength(1)
    expect(root.textContent).not.toContain(":VimDojo daily")
    expect(links()).toEqual([dailyUrl("2026-09-30"), dailyUrl("2026-10-02")])
  })

  it("says when a day has no board", async () => {
    const { api } = apiWith({ "/daily/2030-01-01": { status: 404 } })
    await showDaily(root, api, { ...today, date: "2030-01-01" })
    expect(root.textContent).toContain("no daily board")
  })

  it("reports a failure", async () => {
    const { api } = apiWith({})
    await showDaily(root, api, today)
    expect(root.querySelector("[role=alert]")).not.toBeNull()
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

  it("shows the player's overall place", async () => {
    const { api } = apiWith({
      "/players/ana": {
        status: 200,
        body: {
          handle: "ana",
          joined: "2026-10",
          overall: { rank: 3, handle: "ana", solved: 12, over_par: -1 },
          bests: [],
        },
      },
    })
    await showPlayer(root, heading, api, "ana", NAMES)
    expect(root.textContent).toContain("#3 overall: 12 levels at −1 keys over par.")
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
