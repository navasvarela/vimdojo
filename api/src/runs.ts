// Submitting a run: who may, and whether it is worth replaying.
import { z } from "zod"
import { sha256Hex } from "./crypto"
import { dailyDateOf, todaysDaily } from "./daily"
import { ApiError, Status } from "./http"
import { manifestEntry } from "./manifest"
import type { NewRun, RunRow, RunStatus, RunStore } from "./run-store"

/** Non-best runs are kept this long (PLAN-v3, L12). */
export const RUN_LIFETIME_MS = 90 * 24 * 60 * 60 * 1000
const MAX_KEYS = 2000
const MAX_KEY_NAME_LENGTH = 32

export const RunBody = z
  .object({
    level_id: z.string().min(1).max(128),
    level_hash: z.string().min(1).max(128),
    nvim: z.string().min(1).max(32),
    keys: z.array(z.string().min(1).max(MAX_KEY_NAME_LENGTH)).min(1).max(MAX_KEYS),
    deltas_ms: z.array(z.number().int().nonnegative()).max(MAX_KEYS),
    claimed: z.object({
      keys: z.number().int().positive(),
      seconds: z.number().nonnegative(),
      hinted: z.boolean(),
    }),
  })
  .refine((run) => run.deltas_ms.length === run.keys.length, "one gap per key")

export type RunBody = z.infer<typeof RunBody>

/** Only a run that claims to beat the player's verified best costs a replay. */
function initialStatus(
  ranked: boolean,
  claimedKeys: number,
  bestKeys: number | undefined,
): RunStatus {
  if (!ranked) {
    return "unranked"
  }
  return bestKeys !== undefined && claimedKeys >= bestKeys ? "not_best" : "pending"
}

export type SubmitResult = {
  readonly id: string
  readonly status: RunStatus
  /** A new run, not one seen before. */
  readonly isNew: boolean
  /** It's waiting for a replay it wasn't waiting for before, so one is worth starting now. */
  readonly needsReplay: boolean
}

/**
 * Enters a run seen before into today's daily, which is its own competition: a run
 * that didn't beat the player's all-time best can still be their best today.
 */
async function enterExistingRun(
  store: RunStore,
  run: RunRow,
  date: string,
  now: number,
): Promise<RunStatus> {
  if (run.verified_keys !== null) {
    await store.enterDaily(run.id, now, run.status)
    await store.recordDaily(date, run.user_id, run.level_id, run.verified_keys, run.hinted, now)
    return run.status
  }
  // Skipped back then as not worth replaying. It may be now, unless today's entry beats it.
  const status =
    run.status === "not_best"
      ? initialStatus(true, run.claimed_keys, await store.dailyKeys(run.user_id, date))
      : run.status
  await store.enterDaily(run.id, now, status)
  return status
}

export async function submitRun(
  store: RunStore,
  userId: string,
  body: RunBody,
  now: number,
): Promise<SubmitResult> {
  const entry = manifestEntry(body.level_id)
  if (entry === undefined) {
    throw new ApiError(
      Status.UnprocessableEntity,
      "unknown_level",
      "That level isn't on the leaderboards. Only shipped levels are.",
    )
  }
  if (entry.hash !== body.level_hash) {
    throw new ApiError(
      Status.Conflict,
      "level_changed",
      "That level has changed since this run. Update vimdojo and play it again.",
    )
  }
  // The server's clock decides, never the client: nothing can be backfilled.
  const daily = todaysDaily(now)
  const isDaily = entry.ranked && daily?.levelId === body.level_id
  const logHash = await sha256Hex(JSON.stringify(body.keys))
  const existing = await store.findRun(userId, body.level_hash, logHash)
  if (existing !== undefined) {
    const status =
      isDaily && (existing.daily_at === null || dailyDateOf(existing.daily_at) !== daily.date)
        ? await enterExistingRun(store, existing, daily.date, now)
        : existing.status
    return {
      id: existing.id,
      status,
      isNew: false,
      needsReplay: status === "pending" && existing.status !== "pending",
    }
  }
  // On the daily, the bar is the player's best today, not their best ever.
  const bar = isDaily
    ? await store.dailyKeys(userId, daily.date)
    : await store.bestKeys(userId, body.level_hash)
  const status = initialStatus(entry.ranked, body.claimed.keys, bar)
  const run: NewRun = {
    userId,
    levelId: body.level_id,
    levelHash: body.level_hash,
    logHash,
    keys: body.keys,
    deltasMs: body.deltas_ms,
    nvim: body.nvim,
    claimedKeys: body.claimed.keys,
    claimedSeconds: body.claimed.seconds,
    hinted: body.claimed.hinted,
    status,
    dailyAt: isDaily ? now : null,
    receivedAt: now,
    expiresAt: now + RUN_LIFETIME_MS,
  }
  return {
    id: await store.insertRun(run),
    status,
    isNew: true,
    needsReplay: status === "pending",
  }
}

/** What a player sees of their own run. */
export function publicRun(run: RunRow): Record<string, unknown> {
  return {
    id: run.id,
    level_id: run.level_id,
    status: run.status,
    claimed_keys: run.claimed_keys,
    verified_keys: run.verified_keys,
    received_at: new Date(run.received_at).toISOString(),
  }
}
