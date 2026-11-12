// The daily challenge, ported from lua/vimdojo/daily.lua: one level per UTC
// day, the same in both clients. tests/fixtures/daily.json pins both.
//
// Takes its own narrow shape rather than challenges.ts's Pack: the API imports
// this file, and challenges.ts only builds under Vite.

/**
 * The track of the daily challenge's own pack. It isn't one of the curriculum's tracks:
 * a daily is played on its day, and from the archive after it.
 */
export const DAILY_TRACK = "daily"
export const DIFFICULTY_MAX = 5

type DailyCandidate = {
  readonly id: string
  readonly web_demo?: boolean | undefined
  readonly difficulty?: number | undefined
}
type DailyPack = {
  readonly track?: string | undefined
  readonly daily_start?: string | undefined
  readonly levels: readonly DailyCandidate[]
}

/** Which levels the daily picks from, and from when (see `dailyLevel`). */
export type DailySchedule = {
  /** The pool for days before `start` (see `dailyPool`). */
  readonly legacy: readonly string[]
  /** The daily pack's first day; undefined without a daily pack. */
  readonly start: number | undefined
  /** The daily pack's level ids by difficulty, each sorted: tiers[0] is difficulty 1. */
  readonly tiers: readonly (readonly string[])[]
}

/** One level as the schedule needs it; the API builds these from its manifest. */
export type ScheduleLevel = {
  readonly id: string
  /** In the pool used before the daily pack's start. */
  readonly legacy: boolean
  /** Set on the daily pack's levels only. */
  readonly difficulty: number | undefined
}

const MS_PER_DAY = 86_400_000

// The weekly ramp: the tier (a daily level's difficulty) for each weekday, Monday
// first. Easy at the start of the week, the nastiest edge cases at the weekend.
// Must match daily.lua.
const TIER_OF_WEEKDAY: readonly number[] = [1, 2, 3, 3, 4, 5, 5]
const DAYS_PER_WEEK = 7
// 1970-01-01, day 0, was a Thursday: weekday 3 counting Monday as 0.
const EPOCH_WEEKDAY = 3

// Park-Miller MINSTD: products stay below 2^47, so JavaScript numbers and
// Lua's doubles compute them exactly. Must match daily.lua.
const MODULUS = 2_147_483_647
const MULTIPLIER = 48_271

/**
 * The pool before the daily pack started: the demo levels outside it, sorted by id
 * (see `M.pool` in daily.lua).
 */
export function dailyPool(packs: readonly DailyPack[]): string[] {
  return packs
    .filter((pack) => pack.track !== DAILY_TRACK)
    .flatMap((pack) => pack.levels)
    .filter((level) => level.web_demo === true)
    .map((level) => level.id)
    .sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
}

/** Days since 1970-01-01 UTC. */
export function dayNumber(epochMs: number): number {
  return Math.floor(epochMs / MS_PER_DAY)
}

/** "YYYY-MM-DD", UTC. */
export function dailyDate(day: number): string {
  return new Date(day * MS_PER_DAY).toISOString().slice(0, 10)
}

function swap(order: string[], i: number, j: number): void {
  const first = order[i]
  const second = order[j]
  if (first === undefined || second === undefined) {
    throw new Error(`unreachable: positions ${i} and ${j} are inside the pool`)
  }
  order[i] = second
  order[j] = first
}

function shuffled(pool: readonly string[], cycle: number): string[] {
  const order = [...pool]
  let seed = (cycle % (MODULUS - 1)) + 1
  for (let i = order.length - 1; i >= 1; i--) {
    seed = (seed * MULTIPLIER) % MODULUS
    swap(order, i, seed % (i + 1))
  }
  return order
}

/**
 * Every level once per cycle of `pool.length` days, shuffled per cycle, and
 * never the same level two days running (see `M.pick` in daily.lua).
 */
export function pickDaily(pool: readonly string[], day: number): string | undefined {
  const size = pool.length
  if (size === 0) {
    return undefined
  }
  const cycle = Math.floor(day / size)
  const order = shuffled(pool, cycle)
  if (size > 2 && cycle > 0 && order[0] === shuffled(pool, cycle - 1)[size - 1]) {
    swap(order, 0, 1)
  }
  return order[day % size]
}

const byCodeUnit = (a: string, b: string): number => (a < b ? -1 : a > b ? 1 : 0)

export function buildSchedule(
  levels: readonly ScheduleLevel[],
  start: string | undefined,
): DailySchedule {
  const tiers = Array.from({ length: DIFFICULTY_MAX }, (_, index) =>
    levels
      .filter((level) => level.difficulty === index + 1)
      .map((level) => level.id)
      .sort(byCodeUnit),
  )
  return {
    legacy: levels
      .filter((level) => level.legacy)
      .map((level) => level.id)
      .sort(byCodeUnit),
    start: start === undefined ? undefined : dayNumber(Date.parse(`${start}T00:00:00Z`)),
    tiers,
  }
}

/** The schedule from the packs (see `M.schedule` in daily.lua). */
export function dailySchedule(packs: readonly DailyPack[]): DailySchedule {
  const daily = packs.find((pack) => pack.track === DAILY_TRACK)
  const legacy = new Set(dailyPool(packs))
  const levels = packs.flatMap((pack) =>
    pack.levels.map((level) => ({
      id: level.id,
      legacy: legacy.has(level.id),
      difficulty: pack === daily ? level.difficulty : undefined,
    })),
  )
  return buildSchedule(levels, daily?.daily_start)
}

/** How many days before `day` had `tier`, counting from day 0. */
function tierDaysBefore(day: number, tier: number): number {
  const weekday = (day + EPOCH_WEEKDAY) % DAYS_PER_WEEK
  const week = Math.floor((day + EPOCH_WEEKDAY) / DAYS_PER_WEEK)
  const days = TIER_OF_WEEKDAY.map((other, index) => ({ other, index })).filter(
    ({ other }) => other === tier,
  )
  return week * days.length + days.filter(({ index }) => index < weekday).length
}

function tierOf(day: number): number {
  const tier = TIER_OF_WEEKDAY[(day + EPOCH_WEEKDAY) % DAYS_PER_WEEK]
  if (tier === undefined) {
    throw new Error("unreachable: a weekday is 0 to 6")
  }
  return tier
}

/**
 * The daily level on `day`: from the daily pack by the weekly ramp from its start
 * date, and from the old pool before it (see `M.level_for` in daily.lua).
 */
export function dailyLevel(schedule: DailySchedule, day: number): string | undefined {
  const { start } = schedule
  if (start === undefined || day < start) {
    return pickDaily(schedule.legacy, day)
  }
  // Each tier plays like its own pool under `pickDaily`, one "day" per time the tier
  // comes up. Counting from the start date lines the tier's first cycle up with it,
  // so no level comes back before the whole tier has been played.
  const tier = tierOf(day)
  const occurrence = tierDaysBefore(day, tier) - tierDaysBefore(start, tier)
  return pickDaily(schedule.tiers[tier - 1] ?? [], occurrence)
}

export type PastDaily = { readonly date: string; readonly levelId: string }

/**
 * The daily pack's dailies before `today`, newest first. Days before the pack started
 * aren't included: their levels are in the curriculum anyway.
 */
export function dailyArchive(schedule: DailySchedule, today: number): PastDaily[] {
  const { start } = schedule
  if (start === undefined) {
    return []
  }
  const past: PastDaily[] = []
  for (let day = today - 1; day >= start; day--) {
    const levelId = dailyLevel(schedule, day)
    if (levelId !== undefined) {
      past.push({ date: dailyDate(day), levelId })
    }
  }
  return past
}
