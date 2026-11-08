import { describe, expect, it } from "vitest"
import { demoPacks, loadPacks } from "../challenges"
import { Demo } from "./demo"

// The demo's level list and welcome, rendered without opening a level (which needs
// the emulation, and so real Chromium: see emulation.browser.test.ts).
function render(): HTMLElement {
  const root = document.createElement("div")
  new Demo(root, loadPacks(), undefined)
  return root
}

describe("Demo", () => {
  it("offers the first level and today's daily before anything is picked", () => {
    const first = demoPacks(loadPacks())[0]?.levels[0]
    const buttons = [...render().querySelectorAll(".stage button")].map((b) => b.textContent)
    expect(buttons[0]).toBe(`Start: ${first?.title}`)
    expect(buttons[1]).toMatch(/^Today's daily: /)
  })

  it("says how many of each pack's levels need the plugin", () => {
    const curriculum = loadPacks()
    const pack = demoPacks(curriculum)[0]
    const all = curriculum.find((p) => p.pack === pack?.pack)?.levels.length ?? 0
    const more = render().querySelector(".level-list .more-levels")?.textContent
    expect(more).toBe(`+${all - (pack?.levels.length ?? 0)} more in the plugin`)
  })

  it("lists the packs the browser can't play at all", () => {
    const last = render().querySelector(".level-list > li:last-child")?.textContent
    expect(last).toContain("Neovim only")
    expect(last).toContain("Visual Mode")
  })
})
