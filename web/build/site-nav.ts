import { relative, sep } from "node:path"
import type { Plugin } from "vite"

// The links at the top of every page. Pages are separate HTML files, so the bar is
// written into each at build time from one list instead of being copied by hand.

const PLACEHOLDER = "<!-- site-nav -->"

type NavLink = { readonly label: string; readonly path: string }

const LINKS: readonly NavLink[] = [
  { label: "Play", path: "#play" },
  { label: "Daily", path: "#daily" },
  { label: "Leaderboards", path: "boards/" },
  { label: "Install", path: "#install" },
  { label: "Account", path: "account/" },
]

/** @param page The page's path from the site root, such as "" or "boards/". */
export function renderSiteNav(base: string, page: string): string {
  const items = LINKS.map(({ label, path }) => {
    const current = path === page ? ` aria-current="page"` : ""
    return `<li><a href="${base}${path}"${current}>${label}</a></li>`
  }).join("")
  return `<nav class="site-nav" aria-label="Site"><a class="site-nav-home" href="${base}">vimdojo</a><ul>${items}</ul></nav>`
}

/** @param root The directory the pages' paths are relative to (web/). */
export function siteNavPlugin(root: string): Plugin {
  let base = "/"
  return {
    name: "vimdojo-site-nav",
    configResolved(config) {
      base = config.base
    },
    transformIndexHtml(html, context) {
      const page = relative(root, context.filename)
        .split(sep)
        .join("/")
        .replace(/index\.html$/, "")
      return html.replace(PLACEHOLDER, renderSiteNav(base, page))
    },
  }
}
