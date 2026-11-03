import { describe, expect, it } from "vitest"
import { userEvent } from "vitest/browser"
import fixtureMotions from "../../tests/fixtures/packs/01-v2-motions.json"
import { loadPacks, type Level, type Pack, parsePacks } from "./challenges"
import { createEditor, isNormalMode, snapshot } from "./game/editor"
import { isMet, needsNeovim, registersFor } from "./goals"
import { keyNotation } from "./key-notation"
import { isCountableKeydown, splitNotation } from "./keys"

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

type Attempt = { readonly solved: boolean; readonly recorded: ReadonlyArray<string | undefined> }

async function playInEmulation(level: Level): Promise<Attempt> {
  const parent = document.createElement("div")
  document.body.append(parent)
  const view = createEditor(parent, level, { onChange: () => undefined })
  // What the demo records for each counted key (demo.ts, onKeydown).
  const recorded: Array<string | undefined> = []
  view.dom.addEventListener(
    "keydown",
    (event) => {
      if (!event.metaKey && isCountableKeydown(event)) {
        recorded.push(keyNotation(event))
      }
    },
    { capture: true },
  )
  try {
    view.focus()
    const names = registersFor(level.goal)
    const unsolvedAtStart = !isMet(level.goal, snapshot(view, names), level.start_text)
    for (const key of splitNotation(level.solution)) {
      await userEvent.keyboard(toKeyboard(key))
    }
    const solved =
      unsolvedAtStart &&
      isNormalMode(view) &&
      isMet(level.goal, snapshot(view, names), level.start_text)
    return { solved, recorded }
  } finally {
    view.destroy()
    parent.remove()
  }
}

async function solveInEmulation(level: Level): Promise<boolean> {
  return (await playInEmulation(level)).solved
}

// Setup levels check a Neovim config, which the emulation can't run.
function emulatable(packs: readonly Pack[]): Level[] {
  return packs.flatMap((pack) => pack.levels).filter((level) => !needsNeovim(level.goal))
}

// Their solutions use Vim regex atoms such as \zs and \@<!, and the emulation's
// JavaScript regex throws on those. The errors surface outside the test, so they
// fail the run even though this report is only informational.
const VIM_REGEX_PACKS: ReadonlySet<string> = new Set([
  "regex-power",
  "expression-register",
  "boss-levels",
])

const packs = loadPacks()
const levels = emulatable(packs)
const reportedLevels = emulatable(packs.filter((pack) => !VIM_REGEX_PACKS.has(pack.pack)))

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

  // A web run is replayed in Neovim from these names, so each solution must record
  // as one name per key. The names are logged for checking a replay by hand
  // (verifier/src/cli.ts).
  it.each(levels.filter((l) => l.web_demo === true).map((l) => [l.id, l] as const))(
    "%s records a name for every key",
    async (id, level) => {
      const { solved, recorded } = await playInEmulation(level)
      expect(solved).toBe(true)
      expect(recorded).toHaveLength(splitNotation(level.solution).length)
      expect(recorded).not.toContain(undefined)
      console.info(`WEB_KEYLOG ${JSON.stringify({ level_id: id, keys: recorded })}`)
    },
  )

  it("reports which levels the emulation can solve", async () => {
    const report: string[] = []
    for (const level of reportedLevels) {
      report.push(`${(await solveInEmulation(level)) ? "ok  " : "FAIL"} ${level.id}`)
    }
    console.info(report.join("\n"))
  })
})
