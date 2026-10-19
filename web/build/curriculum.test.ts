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

  it("groups packs by track in curriculum order and badges Neovim-only tracks", () => {
    const html = renderCurriculum(readPacks(CHALLENGES_DIR))
    const motions = html.indexOf('id="track-motions"')
    const usage = html.indexOf('id="track-usage"')
    const setup = html.indexOf('id="track-setup"')
    expect(motions).toBeGreaterThanOrEqual(0)
    expect(motions).toBeLessThan(usage)
    expect(usage).toBeLessThan(setup)
    expect(html.slice(motions, usage)).not.toContain("Neovim only")
    expect(html.slice(usage, setup)).toContain("Neovim only")
    expect(html.slice(setup)).toContain("Neovim only")
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
