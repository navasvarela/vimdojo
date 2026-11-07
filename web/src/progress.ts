import { z } from "zod"
import type { Level, Pack } from "./challenges"

// Port of lua/vimdojo/progress.lua. The shape matches the plugin's
// progress.json so an exported file means the same thing in both.

export const PROGRESS_VERSION = 1

const LevelRecord = z.object({
  best_keys: z.number().int().min(0),
  best_seconds: z.number().min(0),
  stars: z.number().int().min(0).max(3),
  attempts: z.number().int().min(0),
})

const DailyStreak = z.object({
  streak: z.number().int().min(0),
  best: z.number().int().min(0),
  last_day: z.number().int(),
})

const Progress = z.object({
  version: z.literal(PROGRESS_VERSION),
  levels: z.record(z.string(), LevelRecord),
  // `catch`: a bad streak isn't worth discarding every level's record.
  daily: DailyStreak.optional().catch(undefined),
})

export type LevelRecord = z.infer<typeof LevelRecord>
export type Progress = z.infer<typeof Progress>
export type DailyStreak = z.infer<typeof DailyStreak>

export type Result = {
  readonly keys: number
  readonly seconds: number
  readonly stars: number
}

export function emptyProgress(): Progress {
  return { version: PROGRESS_VERSION, levels: {} }
}

/** Validates untrusted progress data (localStorage, an imported file). */
export function parseProgress(data: unknown): Progress | undefined {
  const parsed = Progress.safeParse(data)
  return parsed.success ? parsed.data : undefined
}

/** Each best is tracked independently, so they may come from different attempts. */
export function mergeRecord(previous: LevelRecord | undefined, result: Result): LevelRecord {
  if (previous === undefined) {
    return {
      best_keys: result.keys,
      best_seconds: result.seconds,
      stars: result.stars,
      attempts: 1,
    }
  }
  return {
    best_keys: Math.min(previous.best_keys, result.keys),
    best_seconds: Math.min(previous.best_seconds, result.seconds),
    stars: Math.max(previous.stars, result.stars),
    attempts: previous.attempts + 1,
  }
}

export function recordResult(progress: Progress, levelId: string, result: Result): Progress {
  return {
    ...progress,
    levels: { ...progress.levels, [levelId]: mergeRecord(progress.levels[levelId], result) },
  }
}

/** Port of progress.record_daily; tests/fixtures/streak.json pins both. */
export function recordDaily(progress: Progress, day: number): Progress {
  const { daily } = progress
  if (daily !== undefined && daily.last_day >= day) {
    return progress
  }
  const streak = daily?.last_day === day - 1 ? daily.streak + 1 : 1
  return {
    ...progress,
    daily: { streak, best: Math.max(daily?.best ?? 0, streak), last_day: day },
  }
}

/** Port of progress.current_streak: alive until a whole day has been missed. */
export function currentStreak(progress: Progress, today: number): number {
  const { daily } = progress
  return daily === undefined || daily.last_day < today - 1 ? 0 : daily.streak
}

export function isCompleted(progress: Progress, levelId: string): boolean {
  const record = progress.levels[levelId]
  return record !== undefined && record.stars >= 1
}

/** Whether any of the pack's levels is solved: until one is, the pack is new to the player. */
export function hasSolvedAny(progress: Progress, pack: Pack): boolean {
  return pack.levels.some((level) => isCompleted(progress, level.id))
}

/** Whether the running editor can play a level (see lua/vimdojo/compat.lua). */
export type Supports = (level: Level) => boolean

const supportsEverything: Supports = () => true

/**
 * Port of progress.unlocked_by_progress. Per track (tracks progress
 * independently): a level unlocks when the previous level in its pack is
 * cleared; a pack's first level unlocks when the track's previous pack is
 * cleared. Cleared means completed, or not runnable here.
 */
export function unlockedByProgress(
  progress: Progress,
  packs: readonly Pack[],
  supports: Supports = supportsEverything,
): Set<string> {
  const unlocked = new Set<string>()
  const previousPackCleared = new Map<string, boolean>()
  for (const pack of packs) {
    let previousCleared = previousPackCleared.get(pack.track) ?? true
    for (const level of pack.levels) {
      if (previousCleared) {
        unlocked.add(level.id)
      }
      previousCleared = previousCleared && (isCompleted(progress, level.id) || !supports(level))
    }
    previousPackCleared.set(pack.track, previousCleared)
  }
  return unlocked
}

export function unlockedAll(packs: readonly Pack[]): Set<string> {
  return new Set(packs.flatMap((pack) => pack.levels.map((level) => level.id)))
}
