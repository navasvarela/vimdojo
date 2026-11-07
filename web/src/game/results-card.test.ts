import { describe, expect, it, vi } from "vitest"
import { parsePacks, type Level } from "../challenges"
import { h } from "../ui/dom"
import { SOLUTION_HIDDEN } from "./lesson"
import { type LessonRowsView, lessonRows, onCardKeys, typedSummary } from "./results-card"

function level(explain?: readonly { keys: string; text: string }[]): Level {
  const [pack] = parsePacks([
    {
      pack: "x",
      title: "X",
      order: 1,
      levels: [
        {
          id: "x-1",
          title: "t",
          description: "d",
          start_text: ["a"],
          cursor_start: [1, 0],
          goal: { type: "cursor_at", line: 1, col: 0 },
          par_keys: 3,
          par_seconds: 5,
          hint: "h",
          solution: "d<lt>w",
          teaches: ["dw", "<"],
          ...(explain === undefined ? {} : { explain }),
        },
      ],
    },
  ])
  const parsed = pack?.levels[0]
  if (parsed === undefined) {
    throw new Error("fixture level didn't parse")
  }
  return parsed
}

function rows(view: LessonRowsView): string[] {
  const list = h("dl", {}, lessonRows(view))
  return [...list.children].map((child) => child.textContent ?? "")
}

describe("typedSummary", () => {
  it("shows short attempts whole, with <lt> read as <", () => {
    expect(typedSummary(["d", "<lt>", "w"])).toBe("d<w")
  })

  it("cuts a long attempt with an ellipsis", () => {
    const summary = typedSummary(Array.from({ length: 80 }, () => "j"))
    expect(summary).toBe(`${"j".repeat(60)}…`)
  })
})

describe("lessonRows", () => {
  it("lists the player's keys, the tip, par, what it teaches and the steps", () => {
    const view = {
      level: level([{ keys: "d<lt>w", text: "deletes" }]),
      typed: ["x", "x"],
      tip: "Try dw.",
      solutionHidden: false,
    }
    expect(rows(view)).toEqual([
      "You",
      "xx",
      "Tip",
      "Try dw.",
      "Par",
      "d<w",
      "Learn",
      "dw, <",
      "Steps",
      "d<w deletes",
    ])
  })

  it("leaves out what the attempt couldn't record, and steps the level hasn't got", () => {
    expect(
      rows({ level: level(), typed: undefined, tip: undefined, solutionHidden: false }),
    ).toEqual(["Par", "d<w", "Learn", "dw, <"])
  })

  it("hides the par route and everything that would give it away on today's daily", () => {
    const view = { level: level(), typed: ["x"], tip: undefined, solutionHidden: true }
    expect(rows(view)).toEqual(["You", "x", "Par", SOLUTION_HIDDEN])
  })
})

describe("onCardKeys", () => {
  function press(card: HTMLElement, init: KeyboardEventInit): KeyboardEvent {
    const event = new KeyboardEvent("keydown", { ...init, cancelable: true })
    card.dispatchEvent(event)
    return event
  }

  it("runs the action for a letter in either case", () => {
    const card = h("section")
    const retry = vi.fn()
    onCardKeys(card, { r: retry })
    expect(press(card, { key: "R" }).defaultPrevented).toBe(true)
    press(card, { key: "r" })
    expect(retry).toHaveBeenCalledTimes(2)
  })

  it("leaves other keys, and browser shortcuts, to the browser", () => {
    const card = h("section")
    const retry = vi.fn()
    onCardKeys(card, { r: retry })
    expect(press(card, { key: "Tab" }).defaultPrevented).toBe(false)
    expect(press(card, { key: "r", metaKey: true }).defaultPrevented).toBe(false)
    expect(retry).not.toHaveBeenCalled()
  })
})
