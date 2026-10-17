import { readFileSync, readdirSync } from "node:fs"
import { join } from "node:path"
import type { Plugin } from "vite"
import { parsePacks, type Pack } from "../src/challenges"

// Renders the curriculum section into index.html at build time, straight from
// challenges/*.json, so the landing page lists the real packs without
// shipping the pack data or a parser to the browser.

const PLACEHOLDER = "<!-- curriculum -->"

function escapeHtml(text: string): string {
  return text
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
}

function uniqueTeaches(pack: Pack): string[] {
  return [...new Set(pack.levels.flatMap((level) => level.teaches))]
}

function renderPack(pack: Pack): string {
  const keys = uniqueTeaches(pack)
    .map((key) => `<kbd>${escapeHtml(key)}</kbd>`)
    .join(" ")
  return [
    `<li class="pack">`,
    `<h3><span class="pack-number">${String(pack.order).padStart(2, "0")}</span> ${escapeHtml(pack.title)}</h3>`,
    pack.description === undefined ? "" : `<p>${escapeHtml(pack.description)}</p>`,
    `<p class="pack-keys">${keys}</p>`,
    `<p class="pack-count">${pack.levels.length} levels</p>`,
    `</li>`,
  ].join("")
}

export function readPacks(challengesDir: string): Pack[] {
  const files = readdirSync(challengesDir).filter((name) => /^\d.*\.json$/.test(name))
  return parsePacks(
    files.map((name): unknown => JSON.parse(readFileSync(join(challengesDir, name), "utf8"))),
  )
}

export function renderCurriculum(packs: readonly Pack[]): string {
  return `<ol class="packs">${packs.map(renderPack).join("")}</ol>`
}

/**
 * @param indexHtml Absolute path of the site's index.html. Other HTML that
 *   Vite serves (such as Vitest's browser runner) passes through untouched.
 */
export function curriculumPlugin(challengesDir: string, indexHtml: string): Plugin {
  return {
    name: "vimdojo-curriculum",
    transformIndexHtml(html, context) {
      if (context.filename !== indexHtml) {
        return html
      }
      if (!html.includes(PLACEHOLDER)) {
        throw new Error(`index.html is missing the ${PLACEHOLDER} placeholder`)
      }
      return html.replace(PLACEHOLDER, renderCurriculum(readPacks(challengesDir)))
    },
  }
}
