// Spoiler-free result text, ported from lua/vimdojo/share.lua.
// tests/fixtures/share.json pins both.
import { DIFFICULTY_NAMES, weekdayName } from "./daily"
import { stars } from "./ui/dom"

export const SITE_URL = "https://vimdojo.org"

export type ShareView = {
  readonly levelId: string
  readonly levelTitle: string
  readonly parKeys: number
  readonly dailyDate: string | undefined
  /** Set for the daily pack's levels. */
  readonly difficulty: number | undefined
  readonly outcome: {
    readonly keys: number
    readonly seconds: number
    readonly stars: number
    readonly hinted: boolean
  }
}

/** Rounds half up, like `tenths` in share.lua (see there for why). */
function tenths(seconds: number): string {
  return (Math.floor(seconds * 10 + 0.5) / 10).toFixed(1)
}

/**
 * "daily 2026-11-17 (Tuesday, medium)": the day and how hard it is, so a shared result
 * says the dailies get harder through the week (see `daily_name` in share.lua). Dailies
 * from before the daily pack have no difficulty, and keep the date alone.
 */
function dailyName(date: string, difficulty: number | undefined): string {
  const level = difficulty === undefined ? undefined : DIFFICULTY_NAMES[difficulty - 1]
  return level === undefined ? `daily ${date}` : `daily ${date} (${weekdayName(date)}, ${level})`
}

export function shareText(view: ShareView): string {
  const name =
    view.dailyDate === undefined
      ? `"${view.levelTitle}"`
      : dailyName(view.dailyDate, view.difficulty)
  const { outcome } = view
  const score = `${stars(outcome.stars)} ${outcome.keys} keys (par ${view.parKeys}) ${tenths(outcome.seconds)}s`
  const hint = outcome.hinted ? " · hint" : ""
  // The link names the level and the count, never the keys, so it stays spoiler-free. It
  // goes to the level's share page, which previews as a card (web/build/share-pages.ts).
  const link = `${SITE_URL}/play/${view.levelId}/?beat=${outcome.keys}`
  return `vimdojo ${name} ${score}${hint}\nBeat it: ${link}`
}
