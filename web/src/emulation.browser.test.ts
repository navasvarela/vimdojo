import { describe, expect, it } from "vitest"
import { loadPacks, type Level } from "./challenges"
import { createEditor, isNormalMode, snapshot, typeKeys } from "./game/editor"
import { isMet } from "./goals"

// Runs every level's reference solution through the CodeMirror Vim emulation
// in a real browser.
// Levels flagged web_demo must behave exactly as in Neovim; the rest are
// reported so authors know which ones are safe to flag.

function solveInEmulation(level: Level): boolean {
  const parent = document.createElement("div")
  document.body.append(parent)
  const view = createEditor(parent, level, { onChange: () => undefined })
  try {
    const unsolvedAtStart = !isMet(level.goal, snapshot(view), level.start_text)
    typeKeys(view, level.solution)
    return unsolvedAtStart && isNormalMode(view) && isMet(level.goal, snapshot(view), level.start_text)
  } finally {
    view.destroy()
    parent.remove()
  }
}

const levels = loadPacks().flatMap((pack) => pack.levels)

describe("CodeMirror Vim emulation", () => {
  it.each(levels.filter((l) => l.web_demo === true).map((l) => [l.id, l] as const))(
    "%s (web_demo) solves exactly as in Neovim",
    (_id, level) => {
      expect(solveInEmulation(level)).toBe(true)
    },
  )

  it("reports which levels the emulation can solve", () => {
    const report = levels.map((level) => `${solveInEmulation(level) ? "ok  " : "FAIL"} ${level.id}`)
    console.info(report.join("\n"))
  })
})
