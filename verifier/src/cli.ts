// The verifier's entry point inside the sandbox. Reads a JSON array of jobs
// ({ level_id, level_hash, keys }) from a file and writes a JSON array of verdicts
// on stdout, in the same order.
//
// Levels come from this snapshot's own copy, never from the job, and the hash must
// match: a client can't change a level by submitting a different one.
//
// Usage: node cli.js <plugin-dir> <nvim> <jobs.json> [replay-user]
// With a replay user, this must run as root: each job gets a fresh directory and
// runs as that user, and everything the user left behind goes before the next job.
import { execFileSync } from "node:child_process"
import { chownSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"
import { z } from "zod"
import type { Level } from "../../web/src/challenges"
import { levelHash } from "../../web/src/level-hash"
import { readPacks } from "./packs"
import { type ReplayIdentity, replay, type Verdict } from "./replay"

const TIMEOUT_MS = 10_000
const XDG_DIRS = ["config", "data", "state", "cache"]
// The owner only: no replay can read another's leftovers.
const PRIVATE_DIR = 0o700

const Job = z.object({
  level_id: z.string(),
  level_hash: z.string(),
  keys: z.array(z.string()),
})

function userIds(user: string): { uid: number; gid: number } {
  const id = (flag: string): number =>
    Number(execFileSync("id", [flag, user], { encoding: "utf8" }).trim())
  return { uid: id("-u"), gid: id("-g") }
}

function freshHome(uid: number, gid: number): string {
  const home = mkdtempSync(join(tmpdir(), "vimdojo-replay-"))
  chownSync(home, uid, gid)
  for (const name of XDG_DIRS) {
    const dir = join(home, name)
    mkdirSync(dir, { mode: PRIVATE_DIR })
    chownSync(dir, uid, gid)
  }
  return home
}

/** Kills whatever the replay left running (`:terminal`, `:!cmd &`). pkill exits 1 if none. */
function killAll(user: string): void {
  try {
    execFileSync("pkill", ["-KILL", "-u", user], { stdio: "ignore" })
  } catch {
    // Nothing was left running.
  }
}

type Run = (identity: ReplayIdentity | undefined) => Promise<Verdict>

async function isolated(user: string | undefined, run: Run): Promise<Verdict> {
  if (user === undefined) {
    return run(undefined)
  }
  const { uid, gid } = userIds(user)
  const home = freshHome(uid, gid)
  try {
    return await run({ uid, gid, home })
  } finally {
    killAll(user)
    rmSync(home, { recursive: true, force: true })
  }
}

async function runJob(
  raw: unknown,
  levels: ReadonlyMap<string, Level>,
  options: { pluginDir: string; nvim: string; user: string | undefined },
): Promise<Verdict> {
  const job = Job.safeParse(raw)
  if (!job.success) {
    return { status: "error", reason: "a job needs a level_id, level_hash and keys" }
  }
  const level = levels.get(job.data.level_id)
  if (level === undefined || (await levelHash(level)) !== job.data.level_hash) {
    return { status: "error", reason: "this snapshot doesn't have that version of the level" }
  }
  const { pluginDir, nvim, user } = options
  return isolated(user, (identity) =>
    replay(
      { level, keys: job.data.keys },
      { nvim, pluginDir, timeoutMs: TIMEOUT_MS, ...(identity === undefined ? {} : { identity }) },
    ),
  )
}

async function main(): Promise<void> {
  const [pluginArg, nvim, jobsFile, user] = process.argv.slice(2)
  if (pluginArg === undefined || nvim === undefined || jobsFile === undefined) {
    throw new Error("usage: cli.js <plugin-dir> <nvim> <jobs.json> [replay-user]")
  }
  // Absolute, because each replay starts in its own directory.
  const pluginDir = resolve(pluginArg)
  const jobs: unknown = JSON.parse(readFileSync(jobsFile, "utf8"))
  if (!Array.isArray(jobs)) {
    throw new Error("the jobs file must hold a JSON array of jobs")
  }
  const levels = new Map(
    readPacks(join(pluginDir, "challenges"))
      .flatMap((pack) => pack.levels)
      .map((level) => [level.id, level]),
  )
  const verdicts: Verdict[] = []
  for (const job of jobs) {
    verdicts.push(await runJob(job, levels, { pluginDir, nvim, user }))
  }
  process.stdout.write(`${JSON.stringify(verdicts)}\n`)
}

await main()
