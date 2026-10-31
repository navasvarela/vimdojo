// SQL for runs, bests, verdicts and verifier usage. Times are ms since the epoch.
import { randomId } from "./crypto"

export type RunStatus =
  | "pending"
  | "verified"
  | "mismatch"
  | "rejected"
  | "failed"
  | "unranked"
  | "not_best"

export type RunRow = {
  readonly id: string
  readonly user_id: string
  readonly level_id: string
  readonly level_hash: string
  readonly log_hash: string
  readonly keys: string
  readonly deltas_ms: string
  readonly nvim: string
  readonly claimed_keys: number
  readonly claimed_seconds: number
  readonly hinted: number
  readonly status: RunStatus
  readonly verified_keys: number | null
  readonly attempts: number
  readonly received_at: number
  readonly expires_at: number
}

export type NewRun = {
  readonly userId: string
  readonly levelId: string
  readonly levelHash: string
  readonly logHash: string
  readonly keys: readonly string[]
  readonly deltasMs: readonly number[]
  readonly nvim: string
  readonly claimedKeys: number
  readonly claimedSeconds: number
  readonly hinted: boolean
  readonly status: RunStatus
  readonly receivedAt: number
  readonly expiresAt: number
}

export type BestRow = {
  readonly level_id: string
  readonly level_hash: string
  readonly run_id: string
  readonly keys: number
  readonly seconds: number
  readonly hinted: number
  readonly first_at: number
}

/** A verdict from the cache: solved in this many keys, or null for not solved. */
export type CachedVerdict = { readonly solved_keys: number | null }

export class RunStore {
  constructor(private readonly db: D1Database) {}

  async findRun(userId: string, levelHash: string, logHash: string): Promise<RunRow | undefined> {
    const row = await this.db
      .prepare("SELECT * FROM runs WHERE user_id = ? AND level_hash = ? AND log_hash = ?")
      .bind(userId, levelHash, logHash)
      .first<RunRow>()
    return row ?? undefined
  }

  /** Scoped to the owner: a run is its level's solution. */
  async runOf(userId: string, runId: string): Promise<RunRow | undefined> {
    const row = await this.db
      .prepare("SELECT * FROM runs WHERE id = ? AND user_id = ?")
      .bind(runId, userId)
      .first<RunRow>()
    return row ?? undefined
  }

  async insertRun(run: NewRun): Promise<string> {
    const id = randomId()
    await this.db
      .prepare(
        `INSERT INTO runs (id, user_id, level_id, level_hash, log_hash, keys, deltas_ms, nvim,
           claimed_keys, claimed_seconds, hinted, status, received_at, expires_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .bind(
        id,
        run.userId,
        run.levelId,
        run.levelHash,
        run.logHash,
        JSON.stringify(run.keys),
        JSON.stringify(run.deltasMs),
        run.nvim,
        run.claimedKeys,
        run.claimedSeconds,
        run.hinted ? 1 : 0,
        run.status,
        run.receivedAt,
        run.expiresAt,
      )
      .run()
    return id
  }

  async bestKeys(userId: string, levelHash: string): Promise<number | undefined> {
    const row = await this.db
      .prepare("SELECT keys FROM bests WHERE user_id = ? AND level_hash = ?")
      .bind(userId, levelHash)
      .first<{ keys: number }>()
    return row?.keys
  }

  /** The players waiting longest, so one player's backlog can't starve the rest. */
  async usersWithPending(limit: number): Promise<readonly string[]> {
    const { results } = await this.db
      .prepare(
        `SELECT user_id FROM runs WHERE status = 'pending'
         GROUP BY user_id ORDER BY MIN(received_at) LIMIT ?`,
      )
      .bind(limit)
      .all<{ user_id: string }>()
    return results.map((row) => row.user_id)
  }

  async pendingRuns(userId: string, limit: number): Promise<readonly RunRow[]> {
    const { results } = await this.db
      .prepare(
        "SELECT * FROM runs WHERE user_id = ? AND status = 'pending' ORDER BY received_at LIMIT ?",
      )
      .bind(userId, limit)
      .all<RunRow>()
    return results
  }

  async cachedVerdict(levelHash: string, logHash: string): Promise<CachedVerdict | undefined> {
    const row = await this.db
      .prepare("SELECT solved_keys FROM verdicts WHERE level_hash = ? AND log_hash = ?")
      .bind(levelHash, logHash)
      .first<CachedVerdict>()
    return row ?? undefined
  }

  async cacheVerdict(
    levelHash: string,
    logHash: string,
    solvedKeys: number | null,
    now: number,
  ): Promise<void> {
    await this.db
      .prepare(
        `INSERT INTO verdicts (level_hash, log_hash, solved_keys, checked_at) VALUES (?, ?, ?, ?)
         ON CONFLICT (level_hash, log_hash) DO NOTHING`,
      )
      .bind(levelHash, logHash, solvedKeys, now)
      .run()
  }

  async setStatus(runId: string, status: RunStatus, verifiedKeys: number | null): Promise<void> {
    await this.db
      .prepare("UPDATE runs SET status = ?, verified_keys = ? WHERE id = ?")
      .bind(status, verifiedKeys, runId)
      .run()
  }

  /** Counts a failed try; after the last one the run stops being retried. */
  async recordAttempt(runId: string, maxAttempts: number): Promise<void> {
    await this.db
      .prepare(
        `UPDATE runs SET attempts = attempts + 1,
           status = CASE WHEN attempts + 1 >= ? THEN 'failed' ELSE status END
         WHERE id = ?`,
      )
      .bind(maxAttempts, runId)
      .run()
  }

  /** Keeps the lower count; a tie keeps the earlier run, which ranks ahead. */
  async recordBest(run: RunRow, keys: number): Promise<void> {
    await this.db
      .prepare(
        `INSERT INTO bests (user_id, level_hash, level_id, run_id, keys, seconds, hinted, first_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (user_id, level_hash) DO UPDATE SET
           run_id = excluded.run_id, keys = excluded.keys, seconds = excluded.seconds,
           hinted = excluded.hinted, first_at = excluded.first_at
         WHERE excluded.keys < bests.keys`,
      )
      .bind(
        run.user_id,
        run.level_hash,
        run.level_id,
        run.id,
        keys,
        run.claimed_seconds,
        run.hinted,
        run.received_at,
      )
      .run()
  }

  async batchesThisMonth(month: string): Promise<number> {
    const row = await this.db
      .prepare("SELECT batches FROM verifier_usage WHERE month = ?")
      .bind(month)
      .first<{ batches: number }>()
    return row?.batches ?? 0
  }

  async countBatch(month: string): Promise<void> {
    await this.db
      .prepare(
        `INSERT INTO verifier_usage (month, batches) VALUES (?, 1)
         ON CONFLICT (month) DO UPDATE SET batches = batches + 1`,
      )
      .bind(month)
      .run()
  }

  /** For the player's export: everything stored about their runs. */
  async runsOf(userId: string): Promise<readonly RunRow[]> {
    const { results } = await this.db
      .prepare("SELECT * FROM runs WHERE user_id = ? ORDER BY received_at")
      .bind(userId)
      .all<RunRow>()
    return results
  }

  async bestsOf(userId: string): Promise<readonly BestRow[]> {
    const { results } = await this.db
      .prepare(
        `SELECT level_id, level_hash, run_id, keys, seconds, hinted, first_at
         FROM bests WHERE user_id = ? ORDER BY first_at`,
      )
      .bind(userId)
      .all<BestRow>()
    return results
  }

  /** Expired runs go, except those behind a current best: boards rely on them. */
  async sweep(now: number): Promise<void> {
    await this.db
      .prepare(
        `DELETE FROM runs WHERE expires_at <= ?
           AND id NOT IN (SELECT run_id FROM bests)`,
      )
      .bind(now)
      .run()
  }
}
