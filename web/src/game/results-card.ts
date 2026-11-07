import type { Level } from "../challenges"
import { type Child, h } from "../ui/dom"
import { readableKeys, SOLUTION_HIDDEN } from "./lesson"

// The parts of the results card that a solve and a practice solve share. Ported from
// lesson_lines and typed_summary in lua/vimdojo/results.lua.

// Cut so that a long, wandering attempt doesn't stretch the card. Same as the plugin's.
const MAX_TYPED_LENGTH = 60

/** The player's keys, cut short with an ellipsis once they pass MAX_TYPED_LENGTH. */
export function typedSummary(keys: readonly string[]): string {
  const shown: string[] = []
  let length = 0
  for (const key of keys) {
    length += key.length
    if (length > MAX_TYPED_LENGTH) {
      shown.push("…")
      break
    }
    shown.push(key)
  }
  return readableKeys(shown.join(""))
}

export type LessonRowsView = {
  readonly level: Level
  /** The keys typed, when the attempt could record them. */
  readonly typed: readonly string[] | undefined
  readonly tip: string | undefined
  /** On today's daily, where the par route would give the board away. */
  readonly solutionHidden: boolean
}

/** What the attempt can teach: the player's keys beside the par route, and a tip. */
export function lessonRows({ level, typed, tip, solutionHidden }: LessonRowsView): Child[] {
  const rows: Child[] = []
  const row = (term: string, ...details: Child[]): void => {
    rows.push(h("dt", {}, [term]), h("dd", {}, details))
  }
  if (typed !== undefined && typed.length > 0) {
    row("You", h("code", {}, [typedSummary(typed)]))
  }
  if (tip !== undefined) {
    row("Tip", tip)
  }
  if (solutionHidden) {
    row("Par", SOLUTION_HIDDEN)
    return rows
  }
  row("Par", h("code", {}, [readableKeys(level.solution)]))
  row("Learn", level.teaches.join(", "))
  if (level.explain !== undefined) {
    const steps = level.explain.map((step) =>
      h("li", {}, [h("code", {}, [readableKeys(step.keys)]), ` ${step.text}`]),
    )
    row("Steps", h("ol", { className: "steps" }, steps))
  }
  return rows
}

/**
 * Single-letter shortcuts on a results card, matched without regard to case. A key
 * with no action passes through, so Tab and Enter still reach the card's buttons.
 */
export function onCardKeys(card: HTMLElement, actions: Readonly<Record<string, () => void>>): void {
  card.addEventListener("keydown", (event) => {
    const action = actions[event.key.toLowerCase()]
    if (action !== undefined && !event.altKey && !event.ctrlKey && !event.metaKey) {
      event.preventDefault()
      action()
    }
  })
}
