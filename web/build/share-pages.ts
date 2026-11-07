import { readFileSync } from "node:fs"
import type { Plugin } from "vite"
import type { Level, Pack } from "../src/challenges"
import { SITE_URL } from "../src/share"
import { escapeHtml, readPacks } from "./curriculum"

// One small page per level at /play/<level>/, so a shared result unfurls as a card that
// names the level. Link previews (Slack, Discord, X, Mastodon) read meta tags without
// running scripts, and the site is static on GitHub Pages, so each level needs its own
// HTML file: a query string on the landing page would get the landing page's card.
// The page then sends the visitor on to the demo with the count to beat.

export const SHARE_IMAGE_FILE = "og.png"
const SHARE_IMAGE_SIZE = { width: 1280, height: 640 } as const
const SHARE_IMAGE_ALT = "vimdojo: learn Vim motions by solving tiny puzzles. Every key counts."

export type SharePage = { readonly fileName: string; readonly html: string }

function playPath(levelId: string): string {
  return `play/${levelId}/`
}

function invitation(level: Level): string {
  return level.web_demo === true
    ? "Play it in your browser and try to beat my count."
    : "It's a level in the Neovim plugin: install it and try to beat my count."
}

export type Card = {
  readonly title: string
  readonly description: string
  /** Absolute: previews key cards by it. */
  readonly url: string
}

export function cardTags(card: Card): string {
  const image = `${SITE_URL}/${SHARE_IMAGE_FILE}`
  return [
    `<meta property="og:type" content="website" />`,
    `<meta property="og:site_name" content="vimdojo" />`,
    `<meta property="og:title" content="${escapeHtml(card.title)}" />`,
    `<meta property="og:description" content="${escapeHtml(card.description)}" />`,
    `<meta property="og:url" content="${escapeHtml(card.url)}" />`,
    `<meta property="og:image" content="${image}" />`,
    `<meta property="og:image:width" content="${SHARE_IMAGE_SIZE.width}" />`,
    `<meta property="og:image:height" content="${SHARE_IMAGE_SIZE.height}" />`,
    `<meta property="og:image:alt" content="${escapeHtml(SHARE_IMAGE_ALT)}" />`,
    `<meta name="twitter:card" content="summary_large_image" />`,
  ].join("\n    ")
}

/**
 * The redirect keeps only `beat`, checked again by parseChallenge on arrival, and it's a
 * script rather than a meta refresh because a refresh can't carry the query along.
 */
function redirectScript(base: string, levelId: string): string {
  return [
    `const beat = new URLSearchParams(location.search).get("beat")`,
    `const query = "?play=${levelId}" + (beat === null ? "" : "&beat=" + encodeURIComponent(beat))`,
    `location.replace("${base}" + query)`,
  ].join("\n      ")
}

export function renderSharePage(pack: Pack, level: Level, base: string): string {
  const title = `"${level.title}" · vimdojo`
  const description = `A ${pack.title} level, par ${level.par_keys} keys. ${level.description} ${invitation(level)}`
  const landing = `${base}?play=${level.id}`
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="robots" content="noindex" />
    <meta name="description" content="${escapeHtml(description)}" />
    ${cardTags({ title, description, url: `${SITE_URL}/${playPath(level.id)}` })}
    <title>${escapeHtml(title)}</title>
    <script>
      ${redirectScript(base, level.id)}
    </script>
  </head>
  <body>
    <p><a href="${escapeHtml(landing)}">Play "${escapeHtml(level.title)}" on vimdojo</a></p>
  </body>
</html>
`
}

// The id becomes a path segment and goes into the page's script unescaped, so it must
// match challenges/schema.json's pattern. The JSON schema check runs in CI, but the build
// only sees what zod parsed, which accepts any string.
const LEVEL_ID = /^[a-z0-9]+(-[a-z0-9]+)*$/

export function renderSharePages(packs: readonly Pack[], base: string): SharePage[] {
  return packs.flatMap((pack) =>
    pack.levels.map((level) => {
      if (!LEVEL_ID.test(level.id)) {
        throw new Error(`level id ${JSON.stringify(level.id)} can't be a share page path`)
      }
      return {
        fileName: `${playPath(level.id)}index.html`,
        html: renderSharePage(pack, level, base),
      }
    }),
  )
}

const CARD_PLACEHOLDER = "<!-- card -->"

export type ShareCardsOptions = {
  readonly challengesDir: string
  /** Emitted under a fixed name, because cards need an absolute, stable image URL. */
  readonly imagePath: string
  /** The card for each of the site's own pages, by the absolute path of its HTML. */
  readonly pages: Readonly<Record<string, Card>>
}

/** Fills in the site's own pages' cards, and writes the share pages and the card image. */
export function shareCardsPlugin({ challengesDir, imagePath, pages }: ShareCardsOptions): Plugin {
  let base = "/"
  return {
    name: "vimdojo-share-cards",
    configResolved(config) {
      base = config.base
    },
    transformIndexHtml(html, context) {
      const card = pages[context.filename]
      return card === undefined ? html : html.replace(CARD_PLACEHOLDER, cardTags(card))
    },
    generateBundle() {
      this.emitFile({ type: "asset", fileName: SHARE_IMAGE_FILE, source: readFileSync(imagePath) })
      for (const page of renderSharePages(readPacks(challengesDir), base)) {
        this.emitFile({ type: "asset", fileName: page.fileName, source: page.html })
      }
    },
  }
}
