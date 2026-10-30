// Spoiler-free result text, ported from lua/vimdojo/share.lua.
// tests/fixtures/share.json pins both.
import { stars } from "./ui/dom"

export const SITE_URL = "https://vimdojo.org"

export type ShareView = {
  readonly levelTitle: string
  readonly parKeys: number
  readonly dailyDate: string | undefined
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

export function shareText(view: ShareView): string {
  const name = view.dailyDate === undefined ? `"${view.levelTitle}"` : `daily ${view.dailyDate}`
  const { outcome } = view
  const score = `${stars(outcome.stars)} ${outcome.keys} keys (par ${view.parKeys}) ${tenths(outcome.seconds)}s`
  const hint = outcome.hinted ? " · hint" : ""
  return `vimdojo ${name} ${score}${hint}\n${SITE_URL}`
}
