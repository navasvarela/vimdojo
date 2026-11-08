// @vitest-environment node
import { describe, expect, it } from "vitest"
import { renderSiteNav } from "./site-nav"

describe("site nav", () => {
  it("links every page under the site's base", () => {
    const nav = renderSiteNav("/vimdojo/", "")
    expect(nav).toContain(`<a href="/vimdojo/#daily">Daily</a>`)
    expect(nav).toContain(`<a href="/vimdojo/boards/">Leaderboards</a>`)
    expect(nav).toContain(`<a class="site-nav-home" href="/vimdojo/">vimdojo</a>`)
  })

  it("marks the page it's on, and only that one", () => {
    const nav = renderSiteNav("/", "boards/")
    expect(nav).toContain(`<a href="/boards/" aria-current="page">Leaderboards</a>`)
    expect(nav.match(/aria-current/g)).toHaveLength(1)
  })
})
