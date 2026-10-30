// @vitest-environment node
import { describe, expect, it } from "vitest"
import { parsePacks } from "../src/challenges"
import { credits, renderCredits } from "./credits"

function level(id: string, authors?: string[]) {
  return {
    id,
    title: "t",
    description: "d",
    start_text: ["a"],
    cursor_start: [1, 0],
    goal: { type: "cursor_at", line: 1, col: 0 },
    par_keys: 1,
    par_seconds: 1,
    hint: "h",
    solution: "l",
    teaches: ["l"],
    ...(authors === undefined ? {} : { authors }),
  }
}

describe("credits", () => {
  const packs = parsePacks([
    { pack: "a", title: "A", order: 1, authors: ["ana"], levels: [level("a-1"), level("a-2", ["bo", "ana"])] },
    { pack: "b", title: "B", order: 2, levels: [level("b-1"), level("b-2", ["cy"])] },
  ])

  it("counts levels per author, a level's authors replacing its pack's", () => {
    expect(credits(packs)).toEqual([
      { handle: "ana", levels: 2 },
      { handle: "bo", levels: 1 },
      { handle: "cy", levels: 1 },
    ])
  })

  it("links each author's GitHub profile", () => {
    expect(renderCredits(packs)).toContain('<a href="https://github.com/ana">@ana</a> (2 levels)')
  })

  it("renders nothing when no level is credited", () => {
    expect(renderCredits(parsePacks([{ pack: "c", title: "C", order: 1, levels: [level("c-1")] }]))).toBe("")
  })

  it("rejects handles that aren't GitHub's", () => {
    expect(() => parsePacks([{ pack: "d", title: "D", order: 1, authors: ["@ana"], levels: [level("d-1")] }])).toThrow()
  })
})
