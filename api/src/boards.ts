// What the public can see: counts and handles, never a run's keys (they are the
// level's solution). Self-reported time isn't shown either: it can't be verified,
// and nothing checks that it's plausible yet.
import { type Daily, dailyForDate, todaysDaily } from "./daily"
import { ApiError, Status } from "./http"
import { CURRENT_PARS, type ManifestEntry, manifestEntry } from "./manifest"
import type { OverallRow, RunStore } from "./run-store"

const BOARD_SIZE = 50

function rankedLevel(levelId: string): ManifestEntry {
  const entry = manifestEntry(levelId)
  if (entry === undefined) {
    throw new ApiError(Status.NotFound, "not_found", "No such level.")
  }
  if (!entry.ranked) {
    throw new ApiError(Status.NotFound, "unranked_level", "This level isn't ranked.")
  }
  return entry
}

function isoDay(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10)
}

export async function publicBoard(store: RunStore, levelId: string) {
  const rows = await store.board(rankedLevel(levelId).hash, BOARD_SIZE)
  return {
    level_id: levelId,
    entries: rows.map((row, index) => ({
      rank: index + 1,
      handle: row.handle,
      keys: row.keys,
      hinted: row.hinted === 1,
      since: isoDay(row.first_at),
    })),
  }
}

function requireDaily(daily: Daily | undefined): Daily {
  if (daily === undefined) {
    throw new ApiError(Status.NotFound, "not_found", "There's no daily for that date.")
  }
  return daily
}

/** @param date A day that has happened, or today when left out. */
export async function publicDaily(store: RunStore, now: number, date?: string) {
  const daily = requireDaily(date === undefined ? todaysDaily(now) : dailyForDate(date, now))
  const rows = await store.dailyBoard(daily.date, BOARD_SIZE)
  // The schedule has changed under past days (the pool grew, then the daily pack took
  // over), so a past day's own entries say which level it was, where it has any.
  const playedOn = date === undefined ? undefined : await store.dailyLevelOn(daily.date)
  return {
    date: daily.date,
    level_id: playedOn ?? daily.levelId,
    entries: rows.map((row, index) => ({
      rank: index + 1,
      handle: row.handle,
      keys: row.keys,
      hinted: row.hinted === 1,
    })),
  }
}

export async function ownDailyRank(store: RunStore, userId: string, now: number) {
  const daily = requireDaily(todaysDaily(now))
  const mine = await store.dailyRank(userId, daily.date)
  return {
    date: daily.date,
    level_id: daily.levelId,
    rank: mine?.rank ?? null,
    keys: mine?.keys ?? null,
  }
}

export async function ownRank(store: RunStore, userId: string, levelId: string) {
  const mine = await store.rank(userId, rankedLevel(levelId).hash)
  return { level_id: levelId, rank: mine?.rank ?? null, keys: mine?.keys ?? null }
}

function overallEntry(row: OverallRow) {
  return { rank: row.rank, handle: row.handle, solved: row.solved, over_par: row.over_par }
}

/** Every ranked level at once: the most levels verified, then the fewest keys over par. */
export async function publicOverall(store: RunStore) {
  const rows = await store.overall(CURRENT_PARS, BOARD_SIZE)
  return { entries: rows.map(overallEntry) }
}

export async function ownOverall(store: RunStore, userId: string) {
  const mine = await store.overallOf(CURRENT_PARS, userId)
  return {
    rank: mine?.rank ?? null,
    solved: mine?.solved ?? null,
    over_par: mine?.over_par ?? null,
  }
}

/** The player's own bests with their places, on levels' current versions. */
export async function ownScores(store: RunStore, userId: string) {
  const rows = await store.scores(userId)
  return {
    scores: rows
      .filter((row) => manifestEntry(row.level_id)?.hash === row.level_hash)
      .map((row) => ({
        level_id: row.level_id,
        keys: row.keys,
        rank: row.rank,
        hinted: row.hinted === 1,
        since: isoDay(row.first_at),
      })),
  }
}

/**
 * Only bests on a level's current version: a board for an older one is gone. Hides
 * the join date's day, which says more about a person than a profile needs to.
 */
export async function publicProfile(store: RunStore, handle: string) {
  const profile = await store.profile(handle)
  if (profile === undefined) {
    throw new ApiError(Status.NotFound, "not_found", "No player has that handle.")
  }
  const current = profile.bests.filter(
    (best) => manifestEntry(best.level_id)?.hash === best.level_hash,
  )
  const overall = await store.overallOf(CURRENT_PARS, profile.id)
  return {
    handle,
    joined: new Date(profile.joined).toISOString().slice(0, 7),
    overall: overall === undefined ? null : overallEntry(overall),
    bests: current.map((best) => ({
      level_id: best.level_id,
      keys: best.keys,
      hinted: best.hinted === 1,
      since: isoDay(best.first_at),
    })),
  }
}
