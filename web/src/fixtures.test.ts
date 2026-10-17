import { describe, expect, it } from "vitest"
import { z } from "zod"
import goalsFixture from "../../tests/fixtures/goals.json"
import scoringFixture from "../../tests/fixtures/scoring.json"
import { isMet } from "./goals"
import { score } from "./scoring"
import { parsePacks } from "./challenges"

// The same fixtures drive tests/goals_spec.lua and tests/scoring_spec.lua, so
// the Lua and TS implementations cannot drift apart unnoticed.

const ScoringCase = z.object({
  name: z.string(),
  attempt: z.object({
    keys: z.number(),
    seconds: z.number(),
    par_keys: z.number(),
    par_seconds: z.number(),
    hinted: z.boolean(),
  }),
  expected: z.object({ stars: z.number(), points: z.number() }),
})

// Goal fixtures reuse the pack schema's goal shape by wrapping it in a level.
const GoalCase = z.object({
  name: z.string(),
  goal: z.unknown(),
  start_lines: z.array(z.string()),
  state: z.object({
    lines: z.array(z.string()),
    cursor: z.tuple([z.number(), z.number()]),
    registers: z
      .record(z.string(), z.object({ lines: z.array(z.string()), linewise: z.boolean() }))
      .optional(),
  }),
  expected: z.boolean(),
})

function goalFromFixture(goal: unknown) {
  const [pack] = parsePacks([
    {
      pack: "fixture",
      title: "Fixture",
      order: 1,
      levels: [
        {
          id: "fixture",
          title: "Fixture",
          description: "Fixture",
          start_text: ["x"],
          cursor_start: [1, 0],
          goal,
          par_keys: 1,
          par_seconds: 1,
          hint: "x",
          solution: "x",
          teaches: ["x"],
        },
      ],
    },
  ])
  const level = pack?.levels[0]
  if (level === undefined) {
    throw new Error("fixture level did not parse")
  }
  return level.goal
}

describe("scoring.score (shared fixtures)", () => {
  const cases = z.array(ScoringCase).parse(scoringFixture.cases)
  it.each(cases.map((c) => [c.name, c] as const))("%s", (_name, c) => {
    expect(score(c.attempt)).toEqual(c.expected)
  })
})

describe("goals.isMet (shared fixtures)", () => {
  const cases = z.array(GoalCase).parse(goalsFixture.cases)
  it.each(cases.map((c) => [c.name, c] as const))("%s", (_name, c) => {
    expect(isMet(goalFromFixture(c.goal), c.state, c.start_lines)).toBe(c.expected)
  })
})
