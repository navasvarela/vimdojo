import { StateField, type Extension } from "@codemirror/state"
import { Decoration, EditorView, type DecorationSet } from "@codemirror/view"
import { assertNever } from "../assert"
import type { Level } from "../challenges"
import { byteColToIndex } from "../text"
import { h } from "../ui/dom"

// How each goal type is explained to the player and marked in the editor.
// The single switch here is the place to extend when a goal type is added.

export type GoalPresentation = {
  readonly element: HTMLElement
  readonly extension: Extension
}

const targetMark = Decoration.mark({ class: "cm-vimdojo-target" })

/** Highlights one character and keeps it attached to that text across edits. */
function targetHighlight(level: Level, line: number, byteCol: number): Extension {
  const lineText = level.start_text[line - 1] ?? ""
  const offset =
    level.start_text.slice(0, line - 1).reduce((sum, text) => sum + text.length + 1, 0) +
    byteColToIndex(lineText, byteCol)
  const field = StateField.define<DecorationSet>({
    create: () => Decoration.set([targetMark.range(offset, offset + 1)]),
    update: (decorations, transaction) => decorations.map(transaction.changes),
    provide: (f) => EditorView.decorations.from(f),
  })
  return field
}

export function presentGoal(level: Level): GoalPresentation {
  const goal = level.goal
  switch (goal.type) {
    case "cursor_at":
      return {
        element: h("p", { className: "goal" }, [
          "Goal: put the cursor on the ",
          h("span", { className: "goal-target" }, ["highlighted"]),
          " character.",
        ]),
        extension: targetHighlight(level, goal.line, goal.col),
      }
    case "buffer_equals":
      return {
        element: h("div", { className: "goal" }, [
          h("p", {}, ["Goal: make the text read exactly:"]),
          h("pre", { className: "goal-text" }, [goal.value.join("\n")]),
        ]),
        extension: [],
      }
    default:
      return assertNever(goal)
  }
}
