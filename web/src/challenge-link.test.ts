import { describe, expect, it } from "vitest"
import { challengeResult, parseChallenge } from "./challenge-link"

describe("a challenge link", () => {
  it("reads the level and the count", () => {
    expect(parseChallenge("?play=basic-motions-01&beat=7")).toEqual({
      levelId: "basic-motions-01",
      keys: 7,
    })
  })

  it.each([
    ["no challenge", ""],
    ["no count", "?play=basic-motions-01"],
    ["a count of zero", "?play=basic-motions-01&beat=0"],
    ["a count that isn't a number", "?play=basic-motions-01&beat=7abc"],
    ["an absurd count", "?play=basic-motions-01&beat=99999"],
    ["markup for a level", "?play=%3Cscript%3E&beat=7"],
  ])("ignores %s", (_name, search) => {
    expect(parseChallenge(search)).toBeUndefined()
  })

  it.each([
    [5, "You beat 7 keys by 2. Send them yours."],
    [7, "You matched 7 keys."],
    [9, "2 over 7 keys. Retry (R) to beat it."],
  ])("compares a %i-key solve", (keys, text) => {
    expect(challengeResult({ levelId: "x", keys: 7 }, keys)).toBe(text)
  })
})
