// What the public can see: counts and handles, never a run's keys (they are the
// level's solution). Self-reported time isn't shown either: it can't be verified,
// and nothing checks that it's plausible yet.
import { ApiError, Status } from "./http"
import { type ManifestEntry, manifestEntry } from "./manifest"
import type { RunStore } from "./run-store"

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

export async function ownRank(store: RunStore, userId: string, levelId: string) {
  const mine = await store.rank(userId, rankedLevel(levelId).hash)
  return { level_id: levelId, rank: mine?.rank ?? null, keys: mine?.keys ?? null }
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
  return {
    handle,
    joined: new Date(profile.joined).toISOString().slice(0, 7),
    bests: current.map((best) => ({
      level_id: best.level_id,
      keys: best.keys,
      hinted: best.hinted === 1,
      since: isoDay(best.first_at),
    })),
  }
}
