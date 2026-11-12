// Which levels exist and how they rank, from the committed manifest. The level
// data itself stays out of the Worker: the verifier reads it from its own copy.
import manifest from "../../verifier/manifest.json"
import { buildSchedule, type DailySchedule } from "../../web/src/daily"

export type ManifestEntry = {
  /** In the daily's pool from before the daily pack started. */
  readonly daily: boolean
  /** Set on the daily pack's levels only. */
  readonly difficulty?: number
  readonly hash: string
  readonly par_keys: number
  readonly ranked: boolean
}

const LEVELS: ReadonlyMap<string, ManifestEntry> = new Map(
  Object.entries<ManifestEntry>(manifest.levels),
)

export function manifestEntry(levelId: string): ManifestEntry | undefined {
  return LEVELS.get(levelId)
}

/** Which level is the daily on which day: the plugin and the site build the same. */
export const DAILY_SCHEDULE: DailySchedule = buildSchedule(
  [...LEVELS].map(([id, entry]) => ({ id, legacy: entry.daily, difficulty: entry.difficulty })),
  "daily_start" in manifest && typeof manifest.daily_start === "string"
    ? manifest.daily_start
    : undefined,
)

/**
 * Each ranked level's current version and par, as JSON for SQL's json_each: the overall
 * board counts only bests on a level's current version, measured against its par.
 */
export const CURRENT_PARS: string = JSON.stringify(
  [...LEVELS.values()].filter((entry) => entry.ranked).map((entry) => [entry.hash, entry.par_keys]),
)
