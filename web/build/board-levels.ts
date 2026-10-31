import type { Plugin } from "vite"
import type { Pack } from "../src/challenges"
import { escapeHtml, readPacks } from "./curriculum"

// Lists ranked levels in the boards pages at build time, as the curriculum does, so
// the pages can name levels without shipping the pack data to the browser.

const PLACEHOLDER = "<!-- board-levels -->"
// Setup levels are unranked until their probes can't be forged (PLAN-v3, L5).
const UNRANKED_TRACK = "setup"

export function renderLevelOptions(packs: readonly Pack[]): string {
  return packs
    .filter((pack) => pack.track !== UNRANKED_TRACK)
    .map((pack) => {
      const options = pack.levels
        .map(
          (level) => `<option value="${escapeHtml(level.id)}">${escapeHtml(level.title)}</option>`,
        )
        .join("")
      return `<optgroup label="${escapeHtml(pack.title)}">${options}</optgroup>`
    })
    .join("")
}

/** @param pages Absolute paths of the pages to fill in; others pass through. */
export function boardLevelsPlugin(challengesDir: string, pages: readonly string[]): Plugin {
  return {
    name: "vimdojo-board-levels",
    transformIndexHtml(html, context) {
      return pages.includes(context.filename)
        ? html.replace(PLACEHOLDER, renderLevelOptions(readPacks(challengesDir)))
        : html
    },
  }
}
