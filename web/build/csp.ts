import type { Plugin } from "vite"

// A strict Content-Security-Policy for the pages that show or use data from the
// API: the account page, and boards, which show other players' handles. GitHub Pages can't set headers, so it goes in a
// <meta>, which can't express frame-ancestors. Build only: Vite's dev server
// injects inline styles and a websocket client that this would block.
const HEAD_START = "<head>"

export function accountPolicy(apiOrigin: string): string {
  return [
    "default-src 'none'",
    "script-src 'self'",
    "style-src 'self'",
    // Vite inlines the small logo as a data: URI.
    "img-src 'self' data:",
    `connect-src ${apiOrigin}`,
    "base-uri 'none'",
    "form-action 'none'",
  ].join("; ")
}

export function injectPolicy(html: string, apiOrigin: string): string {
  if (!html.includes(HEAD_START)) {
    throw new Error(`a page has no ${HEAD_START} to put its policy after`)
  }
  const meta = `<meta http-equiv="Content-Security-Policy" content="${accountPolicy(apiOrigin)}" />`
  return html.replace(HEAD_START, `${HEAD_START}\n    ${meta}`)
}

/** @param pages Absolute paths of the pages to protect; others pass through. */
export function accountCspPlugin(pages: readonly string[], apiOrigin: string): Plugin {
  return {
    name: "vimdojo-account-csp",
    apply: "build",
    transformIndexHtml(html, context) {
      return pages.includes(context.filename) ? injectPolicy(html, apiOrigin) : html
    },
  }
}
