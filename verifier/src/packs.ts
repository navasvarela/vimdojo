import { readdirSync, readFileSync } from "node:fs"
import { join } from "node:path"
import { type Pack, parsePacks } from "../../web/src/challenges"

/** The shipped packs, read and validated the same way the site's build does. */
export function readPacks(challengesDir: string): Pack[] {
  const files = readdirSync(challengesDir).filter((name) => /^\d.*\.json$/.test(name))
  return parsePacks(
    files.map((name): unknown => JSON.parse(readFileSync(join(challengesDir, name), "utf8"))),
  )
}
