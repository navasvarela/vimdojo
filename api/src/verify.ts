// The scheduled verifier: replays pending runs and turns verdicts into statuses
// and bests. One sandbox per player, so a hostile log can only affect its owner.
import type { RunRow, RunStore } from "./run-store"

// Each batch makes several calls to Vercel, and a Worker gets 50 per run on the
// free plan. This also lets several players through on each run.
const MAX_PLAYERS_PER_RUN = 3
const MAX_RUNS_PER_BATCH = 10
/** A run that keeps breaking its batch stops being retried after this many tries. */
export const MAX_ATTEMPTS = 3
/**
 * Stops at about 80% of Vercel Sandbox's free 5,000 creations a month, leaving
 * room to investigate. Runs stay pending and resume next month.
 */
export const MONTHLY_BATCH_LIMIT = 4000

export type VerifierJob = {
  readonly level_id: string
  readonly level_hash: string
  readonly keys: readonly string[]
}

export type VerifierVerdict =
  | { readonly status: "solved"; readonly keys: number }
  | { readonly status: "unsolved" }
  | { readonly status: "error"; readonly reason: string }

/** Thrown when a batch ran but its output can't be trusted: its runs count a try. */
export class BadBatchError extends Error {}

export type VerifierRunner = (jobs: readonly VerifierJob[]) => Promise<readonly VerifierVerdict[]>

function monthOf(now: number): string {
  return new Date(now).toISOString().slice(0, 7)
}

async function applyVerdict(
  store: RunStore,
  run: RunRow,
  verdict: VerifierVerdict,
  now: number,
): Promise<void> {
  if (verdict.status === "error") {
    await store.recordAttempt(run.id, MAX_ATTEMPTS)
    return
  }
  const solvedKeys = verdict.status === "solved" ? verdict.keys : null
  await store.cacheVerdict(run.level_hash, run.log_hash, solvedKeys, now)
  if (solvedKeys === null) {
    await store.setStatus(run.id, "rejected", null)
    return
  }
  // Ranked either way: the verifier's count stands, whatever the client claimed.
  await store.setStatus(
    run.id,
    solvedKeys === run.claimed_keys ? "verified" : "mismatch",
    solvedKeys,
  )
  await store.recordBest(run, solvedKeys)
}

async function fromCache(store: RunStore, run: RunRow, now: number): Promise<boolean> {
  const cached = await store.cachedVerdict(run.level_hash, run.log_hash)
  if (cached === undefined) {
    return false
  }
  const verdict: VerifierVerdict =
    cached.solved_keys === null
      ? { status: "unsolved" }
      : { status: "solved", keys: cached.solved_keys }
  await applyVerdict(store, run, verdict, now)
  return true
}

function parseKeys(run: RunRow): readonly string[] {
  const keys: unknown = JSON.parse(run.keys)
  if (!Array.isArray(keys) || !keys.every((key) => typeof key === "string")) {
    throw new Error(`unreachable: run ${run.id} was validated when it was stored`)
  }
  return keys
}

async function verifyPlayer(
  store: RunStore,
  runner: VerifierRunner,
  userId: string,
  now: number,
): Promise<void> {
  const runs = await store.pendingRuns(userId, MAX_RUNS_PER_BATCH)
  const toReplay: RunRow[] = []
  for (const run of runs) {
    if (!(await fromCache(store, run, now))) {
      toReplay.push(run)
    }
  }
  if (toReplay.length === 0) {
    return
  }
  await store.countBatch(monthOf(now))
  let verdicts: readonly VerifierVerdict[]
  try {
    verdicts = await runner(
      toReplay.map((run) => ({
        level_id: run.level_id,
        level_hash: run.level_hash,
        keys: parseKeys(run),
      })),
    )
    if (verdicts.length !== toReplay.length) {
      throw new BadBatchError(`${verdicts.length} verdicts for ${toReplay.length} jobs`)
    }
  } catch (error) {
    if (error instanceof BadBatchError) {
      for (const run of toReplay) {
        await store.recordAttempt(run.id, MAX_ATTEMPTS)
      }
    }
    // Anything else is the runner being unavailable, not the runs' fault: they
    // stay pending, and the caller logs it.
    throw error
  }
  for (const [index, run] of toReplay.entries()) {
    const verdict = verdicts[index]
    if (verdict !== undefined) {
      await applyVerdict(store, run, verdict, now)
    }
  }
}

/** One scheduled run. A player's failure doesn't stop the next player's batch. */
export async function verifyPending(
  store: RunStore,
  runner: VerifierRunner,
  now: number,
): Promise<void> {
  if ((await store.batchesThisMonth(monthOf(now))) >= MONTHLY_BATCH_LIMIT) {
    console.warn("verifier: this month's batch limit is reached; runs stay pending")
    return
  }
  for (const userId of await store.usersWithPending(MAX_PLAYERS_PER_RUN)) {
    try {
      await verifyPlayer(store, runner, userId, now)
    } catch (error) {
      console.error("verifier batch failed:", error instanceof Error ? error.message : error)
    }
  }
}
