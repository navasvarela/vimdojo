import { describe, expect, it, vi } from "vitest"
import type { Lesson } from "../challenges"
import { exampleLine, lessonView } from "./pack-lesson"

const LESSON: Lesson = {
  intro: ["An operator says what to do."],
  commands: [
    {
      keys: "dw",
      text: "Delete to the next word.",
      example: { before: "the fxo jumps", cursor: 4, keys: "dw", after: "the jumps" },
    },
    { keys: "dd", text: "Delete the line." },
  ],
  help: ["operator", "."],
}

describe("exampleLine", () => {
  it.each([
    { before: "the fxo jumps", cursor: 4, parts: ["the ", "f", "xo jumps"] },
    { before: "héllo", cursor: 1, parts: ["h", "é", "llo"] },
    // é is two bytes in UTF-8, so byte 3 is the first l.
    { before: "héllo", cursor: 3, parts: ["hé", "l", "lo"] },
  ])("splits $before at byte $cursor", ({ before, cursor, parts }) => {
    const line = exampleLine({ before, cursor, keys: "x", after: "" })
    expect([line.beforeCursor, line.cursor, line.afterCursor]).toEqual(parts)
  })
})

describe("lessonView", () => {
  it("shows the intro, every command, its example and the help tags", () => {
    const { element } = lessonView("Operate", LESSON)
    expect(element.querySelector("h3")?.textContent).toBe("Operate · lesson")
    expect([...element.querySelectorAll("dt")].map((dt) => dt.textContent)).toEqual(["dw", "dd"])
    expect(element.querySelector(".lesson-cursor")?.textContent).toBe("f")
    expect(element.querySelector(".lesson-example")?.textContent).toBe("the fxo jumpsdwthe jumps")
    expect(element.textContent).toContain(":help operator · :help .")
  })

  it("has no start button unless there's a level to start", () => {
    expect(lessonView("Operate", LESSON).startButton).toBeUndefined()
  })

  it("starts the level from its button", () => {
    const run = vi.fn()
    const { startButton } = lessonView("Operate", LESSON, { label: 'Start "Kill the typo"', run })
    expect(startButton?.textContent).toBe('Start "Kill the typo"')
    startButton?.click()
    expect(run).toHaveBeenCalledOnce()
  })
})
