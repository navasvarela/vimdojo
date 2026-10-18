import { describe, expect, it } from "vitest"
import { userEvent } from "vitest/browser"
import fixtureMotions from "../../tests/fixtures/packs/01-v2-motions.json"
import { loadPacks, parsePacks, type Level } from "./challenges"
import { createEditor, isNormalMode, snapshot } from "./game/editor"
import { isMet, needsNeovim, registersFor } from "./goals"
import { splitNotation } from "./keys"

// Runs every level's reference solution through the CodeMirror Vim emulation
// in real Chromium, pressing real keys (Playwright keyboard events), so the
// search prompt, Insert and Replace mode behave exactly as they do for a
// player. Levels flagged web_demo must behave exactly as in Neovim; the rest
// are reported so authors know which ones are safe to flag.

// Vim key notation -> testing-library keyboard syntax, where `{` and `[` start
// key descriptors and are escaped by doubling.
const NAMED_KEYS: Readonly<Record<string, string>> = {
  "<Esc>": "{Escape}",
  "<CR>": "{Enter}",
  "<BS>": "{Backspace}",
  "<Tab>": "{Tab}",
  "<lt>": "<",
}

function toKeyboard(key: string): string {
  const named = NAMED_KEYS[key]
  if (named !== undefined) {
    return named
  }
  const ctrl = /^<C-(.)>$/.exec(key)
  if (ctrl?.[1] !== undefined) {
    return `{Control>}${ctrl[1]}{/Control}`
  }
  return key === "{" || key === "[" ? key + key : key
}

async function solveInEmulation(level: Level): Promise<boolean> {
  const parent = document.createElement("div")
  document.body.append(parent)
  const view = createEditor(parent, level, { onChange: () => undefined })
  try {
    view.focus()
    const names = registersFor(level.goal)
    const unsolvedAtStart = !isMet(level.goal, snapshot(view, names), level.start_text)
    for (const key of splitNotation(level.solution)) {
      await userEvent.keyboard(toKeyboard(key))
    }
    return (
      unsolvedAtStart &&
      isNormalMode(view) &&
      isMet(level.goal, snapshot(view, names), level.start_text)
    )
  } finally {
    view.destroy()
    parent.remove()
  }
}

// Setup levels check a Neovim config, which the emulation can't run.
const levels = loadPacks()
  .flatMap((pack) => pack.levels)
  .filter((level) => !needsNeovim(level.goal))

describe("CodeMirror Vim emulation", () => {
  it.each(levels.filter((l) => l.web_demo === true).map((l) => [l.id, l] as const))(
    "%s (web_demo) solves exactly as in Neovim",
    async (_id, level) => {
      expect(await solveInEmulation(level)).toBe(true)
    },
  )

  // Register presets and register goals must work in the emulation too.
  const fixtures = parsePacks([fixtureMotions]).flatMap((pack) => pack.levels)
  it.each(
    fixtures
      .filter((l) => l.id === "v2-preset-register" || l.id === "v2-register-goal")
      .map((l) => [l.id, l] as const),
  )("fixture %s solves in the emulation", async (_id, level) => {
    expect(await solveInEmulation(level)).toBe(true)
  })

  it("reports which levels the emulation can solve", async () => {
    const report: string[] = []
    for (const level of levels) {
      report.push(`${(await solveInEmulation(level)) ? "ok  " : "FAIL"} ${level.id}`)
    }
    console.info(report.join("\n"))
  })
})
