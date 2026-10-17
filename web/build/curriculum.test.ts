// @vitest-environment node
import { fileURLToPath } from "node:url"
import { describe, expect, it } from "vitest"
import { parsePacks } from "../src/challenges"
import { readPacks, renderCurriculum } from "./curriculum"

const CHALLENGES_DIR = fileURLToPath(new URL("../../challenges", import.meta.url))

describe("curriculum rendering", () => {
  it("lists every shipped pack in order", () => {
    const packs = readPacks(CHALLENGES_DIR)
    const html = renderCurriculum(packs)
    const positions = packs.map((pack) => html.indexOf(pack.title))
    expect(positions.every((position) => position >= 0)).toBe(true)
    expect(positions).toEqual([...positions].sort((a, b) => a - b))
  })

  it("escapes pack text and lists each taught key once", () => {
    const [pack] = parsePacks([
      {
        pack: "x",
        title: "<Tags> & more",
        order: 1,
        levels: [1, 2].map((n) => ({
          id: `x-${n}`,
          title: "t",
          description: "d",
          start_text: ["a"],
          cursor_start: [1, 0],
          goal: { type: "cursor_at", line: 1, col: 0 },
          par_keys: 1,
          par_seconds: 1,
          hint: "h",
          solution: "l",
          teaches: ["<C-r>"],
        })),
      },
    ])
    const html = renderCurriculum(pack ? [pack] : [])
    expect(html).toContain("&lt;Tags&gt; &amp; more")
    expect(html.match(/&lt;C-r&gt;/g)).toHaveLength(1)
  })
})
