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

  it("says how many of each pack's levels need the plugin, and nothing when none do", () => {
    const curriculum = loadPacks()
    const expected = demoPacks(curriculum)
      .map((pack) => {
        const all = curriculum.find((p) => p.pack === pack.pack)?.levels.length ?? 0
        return all - pack.levels.length
      })
      .filter((more) => more > 0)
      .map((more) => `+${more} more in the plugin`)
    // The last item is the "Neovim only" list, which shares the note's style.
    const packItems = ".level-list > li:not(:last-child)"
    const notes = [...render().querySelectorAll(`${packItems} .more-levels`)].map(
      (note) => note.textContent,
    )
    expect(notes).toEqual(expected)
  })

  it("lists the packs the browser can't play at all", () => {
    const last = render().querySelector(".level-list > li:last-child")?.textContent
    expect(last).toContain("Neovim only")
    expect(last).toContain("Visual Mode")
  })
})
