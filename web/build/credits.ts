import type { Level, Pack } from "../src/challenges"
import { escapeHtml } from "./curriculum"

// Renders the "Levels by" credits line into index.html at build time from
// the packs' and levels' `authors`, like the curriculum.

export const CREDITS_PLACEHOLDER = "<!-- credits -->"

type Credit = { readonly handle: string; readonly levels: number }

/** A level's own authors replace its pack's. */
function authorsOf(pack: Pack, level: Level): readonly string[] {
  return level.authors ?? pack.authors ?? []
}

/** Every credited handle with its level count, most levels first. */
export function credits(packs: readonly Pack[]): Credit[] {
  const counts = new Map<string, number>()
  for (const pack of packs) {
    for (const level of pack.levels) {
      for (const handle of authorsOf(pack, level)) {
        counts.set(handle, (counts.get(handle) ?? 0) + 1)
      }
    }
  }
  return [...counts]
    .map(([handle, levels]) => ({ handle, levels }))
    .sort((a, b) => b.levels - a.levels || (a.handle < b.handle ? -1 : 1))
}

function renderCredit({ handle, levels }: Credit): string {
  const name = escapeHtml(handle)
  const count = levels === 1 ? "1 level" : `${levels} levels`
  return `<a href="https://github.com/${name}">@${name}</a> (${count})`
}

/** Empty when no level is credited, so the line disappears. */
export function renderCredits(packs: readonly Pack[]): string {
  const list = credits(packs)
  if (list.length === 0) {
    return ""
  }
  return `<p class="aside credits">Levels by ${list.map(renderCredit).join(", ")}.</p>`
}
