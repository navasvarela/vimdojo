import { assertNever } from "./assert"
import type { Goal } from "./challenges"

// Port of lua/vimdojo/goals.lua; both are tested against tests/fixtures/goals.json.

export type Register = {
  readonly lines: readonly string[]
  readonly linewise: boolean
}

export type Snapshot = {
  readonly lines: readonly string[]
  /** [line, col]: 1-based line, 0-based UTF-8 byte column. */
  readonly cursor: readonly [number, number]
  /** Only the registers the goal reads (see registersFor). */
  readonly registers?: Readonly<Record<string, Register>> | undefined
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
    case "register_contains": {
      const register = state.registers?.[goal.register]
      if (register === undefined || !linesEqual(register.lines, goal.value)) {
        return false
      }
      return goal.linewise === undefined || goal.linewise === register.linewise
    }
    case "all_of":
      return goal.goals.every((inner) => isMet(inner, state, startLines))
    default:
      return assertNever(goal)
  }
}

/** The registers a snapshot must capture for `goal` to be checked, sorted. */
export function registersFor(goal: Goal): string[] {
  const names = new Set<string>()
  const visit = (g: Goal): void => {
    switch (g.type) {
      case "register_contains":
        names.add(g.register)
        return
      case "all_of":
        g.goals.forEach(visit)
        return
      case "buffer_equals":
      case "cursor_at":
        return
      default:
        assertNever(g)
    }
  }
  visit(goal)
  return [...names].sort()
}
