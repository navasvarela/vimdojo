import type { Plugin } from "vite"

// Adds Cloudflare Web Analytics' cookieless beacon to the deployed site.
// vimdojo.org's DNS is on Cloudflare but not proxied (GitHub Pages serves it
// and must keep renewing its own certificate), so Cloudflare can't inject the
// beacon itself. See "Visit analytics" in docs/decisions.md.

const BEACON_SRC = "https://static.cloudflareinsights.com/beacon.min.js"
const BODY_END = "</body>"

function escapeAttribute(text: string): string {
  return text
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
}

export function renderBeacon(token: string): string {
  const config = escapeAttribute(JSON.stringify({ token }))
  return `<script type="module" src="${BEACON_SRC}" data-cf-beacon="${config}"></script>`
}

/** Returns the HTML unchanged when there is no token (dev, tests, forks). */
export function injectBeacon(html: string, token: string | undefined): string {
  if (token === undefined || token === "") {
    return html
  }
  if (!html.includes(BODY_END)) {
    throw new Error(`index.html has no ${BODY_END} to put the analytics beacon before`)
  }
  return html.replace(BODY_END, `${renderBeacon(token)}\n  ${BODY_END}`)
}

/**
 * @param indexHtml Absolute path of the site's index.html. Other HTML that
 *   Vite serves (such as Vitest's browser runner) passes through untouched.
 * @param token The site's Web Analytics token. It is public by design: it
 *   only identifies which dashboard visits are counted in.
 */
export function analyticsPlugin(indexHtml: string, token: string | undefined): Plugin {
  return {
    name: "vimdojo-analytics",
    transformIndexHtml(html, context) {
      return context.filename === indexHtml ? injectBeacon(html, token) : html
    },
  }
}
