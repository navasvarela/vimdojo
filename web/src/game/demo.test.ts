import { afterEach, describe, expect, it, vi } from "vitest"
import { demoPacks, loadPacks } from "../challenges"
import { DAILY_TRACK } from "../daily"
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

  it("keeps the daily pack's levels out of the level list", () => {
    const daily = loadPacks().find((pack) => pack.track === DAILY_TRACK)
    const listed = [...render().querySelectorAll(".level-list [data-level]")].map((button) =>
      button.getAttribute("data-level"),
    )
    expect(daily?.levels.some((level) => listed.includes(level.id))).toBe(false)
  })
})

describe("Demo after the daily pack starts", () => {
  // A Thursday in the daily pack's first week: Wednesday and Thursday are tier 3.
  const THURSDAY = new Date("2026-11-19T12:00:00Z")
  const daily = loadPacks().find((pack) => pack.track === DAILY_TRACK)
  const titleOf = (id: string | null) => daily?.levels.find((level) => level.id === id)

  afterEach(() => {
    vi.useRealTimers()
  })

  it("picks today's daily from the daily pack, at the weekday's difficulty", () => {
    vi.useFakeTimers({ toFake: ["Date"], now: THURSDAY })
    const label = render().querySelector(".daily .level-button")?.textContent ?? ""
    const level = daily?.levels.find((candidate) => label.endsWith(candidate.title))
    expect(level?.difficulty).toBe(3)
  })

  it("lists the days since the start as past dailies, newest first", () => {
    vi.useFakeTimers({ toFake: ["Date"], now: THURSDAY })
    const past = [...render().querySelectorAll(".past-dailies [data-level]")]
    expect(past.map((button) => button.querySelector(".past-date")?.textContent)).toEqual([
      "2026-11-18",
      "2026-11-17",
      "2026-11-16",
    ])
    expect(past.map((button) => titleOf(button.getAttribute("data-level"))?.difficulty)).toEqual([
      3, 2, 1,
    ])
  })
})
