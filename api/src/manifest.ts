// Which levels exist and how they rank, from the committed manifest. The level
// data itself stays out of the Worker: the verifier reads it from its own copy.
import manifest from "../../verifier/manifest.json"

export type ManifestEntry = {
  readonly daily: boolean
  readonly hash: string
  readonly par_keys: number
  readonly ranked: boolean
}

const LEVELS: ReadonlyMap<string, ManifestEntry> = new Map(Object.entries(manifest.levels))

export function manifestEntry(levelId: string): ManifestEntry | undefined {
  return LEVELS.get(levelId)
}

/** The daily challenge's pool, sorted by id: the plugin and the site pick from the same. */
export const DAILY_POOL: readonly string[] = [...LEVELS]
  .filter(([, entry]) => entry.daily)
  .map(([id]) => id)
  .sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))

/**
 * Each ranked level's current version and par, as JSON for SQL's json_each: the overall
 * board counts only bests on a level's current version, measured against its par.
 */
export const CURRENT_PARS: string = JSON.stringify(
  [...LEVELS.values()].filter((entry) => entry.ranked).map((entry) => [entry.hash, entry.par_keys]),
)
