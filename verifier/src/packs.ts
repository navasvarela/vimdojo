import { readdirSync, readFileSync } from "node:fs"
import { join } from "node:path"
import { type Level, type Pack, parsePacks } from "../../web/src/challenges"

/** The shipped packs, read and validated the same way the site's build does. */
export function readPacks(challengesDir: string): Pack[] {
  const files = readdirSync(challengesDir).filter((name) => /^\d.*\.json$/.test(name))
  return parsePacks(
    files.map((name): unknown => JSON.parse(readFileSync(join(challengesDir, name), "utf8"))),
  )
}

/** Parses one level the way a pack would, so a job's level is validated too. */
export function parseLevel(raw: unknown): Level {
  const [pack] = parsePacks([{ pack: "job", title: "job", order: 1, levels: [raw] }])
  const level = pack?.levels[0]
  if (level === undefined) {
    throw new Error("unreachable: parsePacks returns the pack it was given")
  }
  return level
}
