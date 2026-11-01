import { describe, expect, it } from "vitest"
import { readableKeys } from "./lesson"

describe("readableKeys", () => {
  it.each([
    ["jjjll", "jjjll"],
    ["$hi<lt>cmd>nohlsearch<lt>CR><Esc>", "$hi<cmd>nohlsearch<CR><Esc>"],
  ])("shows %s as %s", (keys, shown) => {
    expect(readableKeys(keys)).toBe(shown)
  })
})
