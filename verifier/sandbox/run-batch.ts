// Runs one verification batch in a sandbox resumed from the verifier
// snapshot, the way the API will: every Motions and Usage reference solution
// as a job, no network, one command. Prints the verdicts and timings.
//
// Usage (from verifier/, after `npm run build`):
//   VERCEL_TOKEN=... VERCEL_TEAM_ID=... VERCEL_PROJECT_ID=... \
//   VERIFIER_SNAPSHOT_ID=... node dist/run-batch.js
import { fileURLToPath } from "node:url"
import { Sandbox } from "@vercel/sandbox"
import { splitNotation } from "../../web/src/keys"
import { readPacks } from "../src/packs"
import { env, REGION, SANDBOX_PATHS } from "./config"

const ROOT = fileURLToPath(new URL("../..", import.meta.url))
const RANKED_TRACKS: ReadonlySet<string> = new Set(["motions", "usage"])
const JOBS_PATH = "jobs.json"
// Generous for a spike: 66 replays take well under a second locally.
const BATCH_TIMEOUT_MS = 120_000

function seconds(since: number): string {
  return `${((performance.now() - since) / 1000).toFixed(2)} s`
}

async function main(): Promise<void> {
  const levels = readPacks(`${ROOT}challenges`)
    .filter((pack) => RANKED_TRACKS.has(pack.track))
    .flatMap((pack) => pack.levels)
  const jobs = levels.map((level) => ({ level, keys: splitNotation(level.solution) }))

  const started = performance.now()
  const sandbox = await Sandbox.create({
    token: env("VERCEL_TOKEN"),
    teamId: env("VERCEL_TEAM_ID"),
    projectId: env("VERCEL_PROJECT_ID"),
    source: { type: "snapshot", snapshotId: env("VERIFIER_SNAPSHOT_ID") },
    region: REGION,
    networkPolicy: "deny-all",
    resources: { vcpus: 1 },
    timeout: BATCH_TIMEOUT_MS,
  })
  console.log(`sandbox ready in ${seconds(started)}`)
  try {
    await sandbox.writeFiles([{ path: JOBS_PATH, content: Buffer.from(JSON.stringify(jobs)) }])
    const replayStarted = performance.now()
    const result = await sandbox.runCommand({
      cmd: "node",
      args: [SANDBOX_PATHS.cli, SANDBOX_PATHS.plugin, SANDBOX_PATHS.nvim, JOBS_PATH],
    })
    const stdout = await result.stdout()
    console.log(`${jobs.length} replays in ${seconds(replayStarted)} (exit ${result.exitCode})`)
    const verdicts: unknown = JSON.parse(stdout)
    if (!Array.isArray(verdicts)) {
      throw new Error(`unexpected output: ${stdout.slice(0, 500)}`)
    }
    const failures = jobs.flatMap((job, index) => {
      const verdict: unknown = verdicts[index]
      const ok =
        typeof verdict === "object" &&
        verdict !== null &&
        "status" in verdict &&
        verdict.status === "solved" &&
        "keys" in verdict &&
        verdict.keys === job.keys.length
      return ok ? [] : [`${job.level.id}: ${JSON.stringify(verdict)}`]
    })
    console.log(`${jobs.length - failures.length}/${jobs.length} verified in the sandbox`)
    for (const failure of failures) {
      console.log(`  ✗ ${failure}`)
    }
    console.log(`total ${seconds(started)}`)
    process.exitCode = failures.length === 0 ? 0 : 1
  } finally {
    await sandbox.stop()
  }
}

await main()
