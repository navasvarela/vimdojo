// The boards and profile pages. Handles come from other players, so they're only
// ever added as text, and only go into a URL encoded.
import { h } from "../ui/dom"
import type { BoardEntry, BoardsApi, OwnRank, Player } from "./api"

const HINT_NOTE = "* used the hint, which doesn't change the rank."
const LOAD_FAILED = "Couldn't load this. Check your connection and try again."

export function playerUrl(handle: string): string {
  return `/player/?handle=${encodeURIComponent(handle)}`
}

export function boardUrl(levelId: string): string {
  return `/boards/?level=${encodeURIComponent(levelId)}`
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
    root.replaceChildren(
      h("p", { className: "aside" }, [`Playing since ${player.joined}.`]),
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
