import { readFileSync, readdirSync } from "node:fs"
import { join } from "node:path"
import type { Plugin } from "vite"
import { TRACKS, parsePacks, type Pack, type Track } from "../src/challenges"
import { CREDITS_PLACEHOLDER, renderCredits } from "./credits"

// Renders the curriculum section (and its credits line, see credits.ts) into
// index.html at build time, straight from challenges/*.json, so the landing page lists the real packs without
// shipping the pack data or a parser to the browser.

const PLACEHOLDER = "<!-- curriculum -->"

export function escapeHtml(text: string): string {
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
    `<h4><span class="pack-number">${String(pack.order).padStart(2, "0")}</span> ${escapeHtml(pack.title)}</h4>`,
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

type TrackInfo = {
  readonly title: string
  readonly blurb: string
  /** The browser demo can't play it: it needs files, windows or a config. */
  readonly neovimOnly: boolean
}

const TRACK_INFO = {
  motions: {
    title: "Motions",
    blurb: "The editing language: from hjkl to text objects, registers, macros and Ex commands.",
    neovimOnly: false,
  },
  usage: {
    title: "Usage",
    blurb: "Working in Neovim: windows, buffers, the quickfix list and the defaults it ships with. Each level opens a small project of real files.",
    neovimOnly: true,
  },
  setup: {
    title: "Setup",
    blurb: "Write and fix an init.lua. Your config runs in a sandboxed Neovim that checks what it does, and shows you as you type what still fails.",
    neovimOnly: true,
  },
} as const satisfies Record<Track, TrackInfo>

function levelCount(packs: readonly Pack[]): number {
  return packs.reduce((sum, pack) => sum + pack.levels.length, 0)
}

function renderTrack(track: Track, packs: readonly Pack[]): string {
  const info = TRACK_INFO[track]
  const badge = info.neovimOnly ? ` <span class="badge">Neovim only</span>` : ""
  return [
    `<section class="track" aria-labelledby="track-${track}">`,
    `<h3 class="track-title" id="track-${track}">${escapeHtml(info.title)}${badge}`,
    ` <span class="track-count">${levelCount(packs)} levels</span></h3>`,
    `<p class="track-blurb">${escapeHtml(info.blurb)}</p>`,
    `<ol class="packs">${packs.map(renderPack).join("")}</ol>`,
    `</section>`,
  ].join("")
}

/** One section per track, in curriculum order; tracks with no packs are left out. */
export function renderCurriculum(packs: readonly Pack[]): string {
  return TRACKS.map((track) => [track, packs.filter((pack) => pack.track === track)] as const)
    .filter(([, trackPacks]) => trackPacks.length > 0)
    .map(([track, trackPacks]) => renderTrack(track, trackPacks))
    .join("")
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
      for (const placeholder of [PLACEHOLDER, CREDITS_PLACEHOLDER]) {
        if (!html.includes(placeholder)) {
          throw new Error(`index.html is missing the ${placeholder} placeholder`)
        }
      }
      const packs = readPacks(challengesDir)
      return html
        .replace(PLACEHOLDER, renderCurriculum(packs))
        .replace(CREDITS_PLACEHOLDER, renderCredits(packs))
    },
  }
}
