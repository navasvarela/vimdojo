// @vitest-environment node
import { describe, expect, it } from "vitest"
import { z } from "zod"
import fixture from "../../tests/fixtures/level_hash.json"
import manifest from "../../verifier/manifest.json"
import { loadPacks, parsePacks } from "./challenges"
import { canonicalLevel, levelHash } from "./level-hash"

const Case = z.object({
  name: z.string(),
  level: z.unknown(),
  canonical: z.string(),
  hash: z.string(),
})

function parseLevel(level: unknown) {
  const parsed = parsePacks([{ pack: "p", title: "P", order: 1, levels: [level] }])[0]?.levels[0]
  if (parsed === undefined) {
    throw new Error("the fixture level did not parse")
  }
  return parsed
}

describe("levelHash (shared fixtures)", () => {
  const cases = z.array(Case).parse(fixture.cases)
  it.each(cases.map((c) => [c.name, c] as const))("%s", async (_name, c) => {
    const level = parseLevel(c.level)
    expect(canonicalLevel(level)).toBe(c.canonical)
    expect(await levelHash(level)).toBe(c.hash)
  })
})

const Manifest = z.record(z.string(), z.object({ hash: z.string(), ranked: z.boolean() }))

describe("verifier/manifest.json", () => {
  it("agrees with this port on every shipped level's hash", async () => {
    const expected = Manifest.parse(manifest.levels)
    const levels = loadPacks().flatMap((pack) =>
      pack.levels.map((level) => ({ level, ranked: pack.track !== "setup" })),
    )
    const actual = await Promise.all(
      levels.map(
        async ({ level, ranked }) => [level.id, { hash: await levelHash(level), ranked }] as const,
      ),
    )
    expect(Object.fromEntries(actual)).toEqual(expected)
  })
})
