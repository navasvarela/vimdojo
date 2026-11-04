// The boards and profile pages. Handles come from other players, so they're only
// ever added as text, and only go into a URL encoded.
import { dailyDate, dayNumber } from "../daily"
import { h } from "../ui/dom"
import type {
  BoardEntry,
  BoardsApi,
  DailyBoard,
  OverallEntry,
  OwnOverall,
  OwnRank,
  Player,
} from "./api"

const HINT_NOTE = "* used the hint, which doesn't change the rank."
const LOAD_FAILED = "Couldn't load this. Check your connection and try again."

export function playerUrl(handle: string): string {
  return `/player/?handle=${encodeURIComponent(handle)}`
}

export function boardUrl(levelId: string): string {
  return `/boards/?level=${encodeURIComponent(levelId)}`
}

export function dailyUrl(date: string): string {
  return `/boards/?daily=${encodeURIComponent(date)}`
}

function failure(): HTMLElement {
  return h("p", { className: "demo-message", attrs: { role: "alert" } }, [LOAD_FAILED])
}

function keysCell(keys: number, hinted: boolean): string {
  return `${keys}${hinted ? "*" : ""}`
}

function table(headings: readonly string[], rows: readonly HTMLElement[]): HTMLElement {
  return h("table", { className: "board" }, [
    h("thead", {}, [
      h(
        "tr",
        {},
        headings.map((text) => h("th", {}, [text])),
      ),
    ]),
    h("tbody", {}, rows),
  ])
}

function boardRow(entry: BoardEntry, mine: OwnRank | undefined): HTMLElement {
  return h("tr", mine?.rank === entry.rank ? { className: "board-mine" } : {}, [
    h("td", {}, [String(entry.rank)]),
    h("td", {}, [h("a", { attrs: { href: playerUrl(entry.handle) } }, [entry.handle])]),
    h("td", {}, [keysCell(entry.keys, entry.hinted)]),
    h("td", {}, [entry.since]),
  ])
}

export async function showBoard(root: HTMLElement, api: BoardsApi, levelId: string): Promise<void> {
  try {
    // The player's place is extra: failing to get it shouldn't lose the board.
    const [entries, mine] = await Promise.all([
      api.board(levelId),
      api.ownRank(levelId).catch(() => undefined),
    ])
    const place =
      mine?.rank != null
        ? h("p", { className: "account-status" }, [`You're #${mine.rank}, with ${mine.keys} keys.`])
        : ""
    if (entries.length === 0) {
      root.replaceChildren(place, h("p", {}, ["No verified runs yet. Yours could be the first."]))
      return
    }
    root.replaceChildren(
      place,
      table(
        ["#", "Player", "Keys", "Since"],
        entries.map((entry) => boardRow(entry, mine)),
      ),
      entries.some((entry) => entry.hinted) ? h("p", { className: "aside" }, [HINT_NOTE]) : "",
    )
  } catch {
    root.replaceChildren(failure())
  }
}

/** "+3", "0" or "−2": keys over par, which beating par makes negative. */
export function overParText(overPar: number): string {
  if (overPar > 0) {
    return `+${overPar}`
  }
  return overPar < 0 ? `−${-overPar}` : "0"
}

function overallRow(entry: OverallEntry, mine: OwnOverall | undefined): HTMLElement {
  return h("tr", mine?.rank === entry.rank ? { className: "board-mine" } : {}, [
    h("td", {}, [String(entry.rank)]),
    h("td", {}, [h("a", { attrs: { href: playerUrl(entry.handle) } }, [entry.handle])]),
    h("td", {}, [String(entry.solved)]),
    h("td", {}, [overParText(entry.over_par)]),
  ])
}

export async function showOverall(root: HTMLElement, api: BoardsApi): Promise<void> {
  try {
    // The player's place is extra: failing to get it shouldn't lose the board.
    const [entries, mine] = await Promise.all([
      api.overall(),
      api.ownOverall().catch(() => undefined),
    ])
    const place =
      mine?.rank != null && mine.solved !== null && mine.over_par !== null
        ? h("p", { className: "account-status" }, [
            `You're #${mine.rank}, with ${mine.solved} levels at ${overParText(mine.over_par)} keys over par.`,
          ])
        : ""
    root.replaceChildren(
      place,
      entries.length === 0
        ? h("p", {}, ["No verified runs yet. Yours could be the first."])
        : table(
            ["#", "Player", "Levels", "Keys over par"],
            entries.map((entry) => overallRow(entry, mine)),
          ),
    )
  } catch {
    root.replaceChildren(failure())
  }
}

export type DailyView = {
  /** A past day, or undefined for today. */
  readonly date: string | undefined
  /** What the player's clock says today is: no link goes past it. */
  readonly now: number
  readonly levelNames: ReadonlyMap<string, string>
}

function dailyRow(entry: DailyBoard["entries"][number], mine: OwnRank | undefined): HTMLElement {
  return h("tr", mine?.rank === entry.rank ? { className: "board-mine" } : {}, [
    h("td", {}, [String(entry.rank)]),
    h("td", {}, [h("a", { attrs: { href: playerUrl(entry.handle) } }, [entry.handle])]),
    h("td", {}, [keysCell(entry.keys, entry.hinted)]),
  ])
}

function dayLink(date: string, offset: number, text: string): HTMLElement {
  const day = dayNumber(Date.parse(`${date}T00:00:00Z`)) + offset
  return h("a", { attrs: { href: dailyUrl(dailyDate(day)) } }, [text])
}

/** Every day's board stays up, one link away from the next. */
function dayLinks(date: string, now: number): HTMLElement {
  const today = dailyDate(dayNumber(now))
  return h("p", { className: "aside" }, [
    dayLink(date, -1, "Previous day"),
    ...(date < today ? [" · ", dayLink(date, 1, "Next day")] : []),
  ])
}

export async function showDaily(root: HTMLElement, api: BoardsApi, view: DailyView): Promise<void> {
  try {
    const isToday = view.date === undefined
    // The player's place is extra: failing to get it shouldn't lose the board.
    const [board, mine] = await Promise.all([
      api.daily(view.date),
      isToday ? api.ownDailyRank().catch(() => undefined) : undefined,
    ])
    if (board === undefined) {
      root.replaceChildren(h("p", {}, ["There's no daily board for that day."]))
      return
    }
    const level = view.levelNames.get(board.level_id) ?? board.level_id
    const place =
      mine?.rank != null
        ? h("p", { className: "account-status" }, [`You're #${mine.rank}, with ${mine.keys} keys.`])
        : ""
    root.replaceChildren(
      h("p", {}, [
        `${board.date}: ${level}. `,
        ...(isToday ? [h("code", {}, [":VimDojo daily"]), " to play it."] : []),
      ]),
      place,
      board.entries.length === 0
        ? h("p", {}, ["No verified runs yet. Yours could be the first."])
        : table(
            ["#", "Player", "Keys"],
            board.entries.map((entry) => dailyRow(entry, mine)),
          ),
      board.entries.some((entry) => entry.hinted)
        ? h("p", { className: "aside" }, [HINT_NOTE])
        : "",
      dayLinks(board.date, view.now),
    )
  } catch {
    root.replaceChildren(failure())
  }
}

function bestRow(best: Player["bests"][number], levelNames: ReadonlyMap<string, string>) {
  return h("tr", {}, [
    h("td", {}, [
      h("a", { attrs: { href: boardUrl(best.level_id) } }, [
        levelNames.get(best.level_id) ?? best.level_id,
      ]),
    ]),
    h("td", {}, [keysCell(best.keys, best.hinted)]),
    h("td", {}, [best.since]),
  ])
}

export async function showPlayer(
  root: HTMLElement,
  heading: HTMLElement,
  api: BoardsApi,
  handle: string | null,
  levelNames: ReadonlyMap<string, string>,
): Promise<void> {
  const notFound = (): void => {
    root.replaceChildren(h("p", {}, ["No player has that handle."]))
  }
  if (handle === null || handle === "") {
    notFound()
    return
  }
  try {
    const player = await api.player(handle)
    if (player === undefined) {
      notFound()
      return
    }
    heading.textContent = player.handle
    const overall = player.overall
    root.replaceChildren(
      h("p", { className: "aside" }, [`Playing since ${player.joined}.`]),
      overall === null
        ? ""
        : h("p", { className: "account-status" }, [
            `#${overall.rank} overall: ${overall.solved} levels at ${overParText(overall.over_par)} keys over par.`,
          ]),
      player.bests.length === 0
        ? h("p", {}, ["No verified scores yet."])
        : table(
            ["Level", "Verified keys", "Since"],
            player.bests.map((best) => bestRow(best, levelNames)),
          ),
      player.bests.some((best) => best.hinted) ? h("p", { className: "aside" }, [HINT_NOTE]) : "",
    )
  } catch {
    root.replaceChildren(failure())
  }
}
