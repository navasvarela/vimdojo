import { assertNever } from "./assert"
import type { Goal } from "./challenges"

// Port of lua/vimdojo/goals.lua; both are tested against tests/fixtures/goals.json.

export type Snapshot = {
  readonly lines: readonly string[]
  /** [line, col]: 1-based line, 0-based UTF-8 byte column. */
  readonly cursor: readonly [number, number]
}

function linesEqual(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((line, i) => line === b[i])
}

export function isMet(goal: Goal, state: Snapshot, startLines: readonly string[]): boolean {
  switch (goal.type) {
    case "buffer_equals":
      return linesEqual(state.lines, goal.value)
    case "cursor_at": {
      const onTarget = state.cursor[0] === goal.line && state.cursor[1] === goal.col
      return onTarget && (goal.allow_edit === true || linesEqual(state.lines, startLines))
    }
    default:
      return assertNever(goal)
  }
}
