// Checks a snapshot the way the API uses it: every Motions and Usage reference
// solution as a job, then hostile logs trying to get out of their replay. Run as
// root with an unprivileged replay user and no network, as in production.
//
// Usage (from verifier/, after `npm run build && npm run build:sandbox`):
//   set -a; . ./.env; set +a; node dist/run-batch.js
import { fileURLToPath } from "node:url"
import { Sandbox } from "@vercel/sandbox"
import type { Level } from "../../web/src/challenges"
import { splitNotation } from "../../web/src/keys"
import { levelHash } from "../../web/src/level-hash"
import { readPacks } from "../src/packs"
import { env, REGION, SANDBOX_PATHS } from "./config"

const ROOT = fileURLToPath(new URL("../..", import.meta.url))
const RANKED_TRACKS: ReadonlySet<string> = new Set(["motions", "usage"])
const JOBS_PATH = "jobs.json"
const BATCH_TIMEOUT_MS = 240_000
const HOSTILE_LEVEL = "basic-motions-01"
// Each hostile log tries something, then solves the level, so its verdict shows the
// replay carried on. They write what they find to files that the checks read back.
const SOLVE = "jjjll"

type Verdict = { status: string; keys?: number; reason?: string }

function seconds(since: number): string {
  return `${((performance.now() - since) / 1000).toFixed(2)} s`
}

/** Hostile logs, as `:!cmd<CR>` keys. All but the first expect to be refused. */
const HOSTILE: ReadonlyArray<{ name: string; notation: string }> = [
  { name: "who am I", notation: ":!id -u > /tmp/hostile-uid<CR>" },
  {
    name: "read the jobs file",
    notation: ":!cat jobs.json /vercel/sandbox/jobs.json > /tmp/hostile-jobs 2>&1<CR>",
  },
  {
    name: "overwrite the harness",
    notation: ":!echo pwned >> /vercel/sandbox/vimdojo/cli.js; echo $? > /tmp/hostile-write<CR>",
  },
  {
    name: "reach the network",
    notation:
      ":!curl -sS -m 3 https://example.com > /tmp/hostile-net 2>&1; echo $? >> /tmp/hostile-net<CR>",
  },
  {
    name: "kill the harness",
    notation: ":!pkill -9 -x node; echo $? > /tmp/hostile-kill<CR>",
  },
  { name: "leave a process behind", notation: ":!sleep 300 &<CR>" },
]

async function shell(sandbox: Sandbox, script: string): Promise<string> {
  const result = await sandbox.runCommand({ cmd: "sh", args: ["-c", script], sudo: true })
  return (await result.stdout()).trim()
}

function check(name: string, ok: boolean, detail = ""): boolean {
  console.log(`  ${ok ? "ok" : "FAILED"}: ${name}${detail === "" ? "" : ` (${detail})`}`)
  return ok
}

async function jobFor(level: Level, keys: readonly string[]) {
  return { level_id: level.id, level_hash: await levelHash(level), keys }
}

async function runJobs(sandbox: Sandbox, jobs: readonly unknown[]): Promise<Verdict[]> {
  await sandbox.writeFiles([{ path: JOBS_PATH, content: Buffer.from(JSON.stringify(jobs)) }])
  await shell(sandbox, `chown root:root ${JOBS_PATH}; chmod 600 ${JOBS_PATH}`)
  const result = await sandbox.runCommand({
    cmd: "node",
    args: [
      SANDBOX_PATHS.cli,
      SANDBOX_PATHS.plugin,
      SANDBOX_PATHS.nvim,
      JOBS_PATH,
      SANDBOX_PATHS.replayUser,
    ],
    sudo: true,
  })
  const stdout = await result.stdout()
  if (result.exitCode !== 0) {
    throw new Error(`the harness exited with ${result.exitCode}: ${await result.stderr()}`)
  }
  return JSON.parse(stdout)
}

async function checkSolutions(sandbox: Sandbox, levels: readonly Level[]): Promise<boolean> {
  const jobs = await Promise.all(
    levels.map((level) => jobFor(level, splitNotation(level.solution))),
  )
  const started = performance.now()
  const verdicts = await runJobs(sandbox, jobs)
  const failures = jobs.flatMap((job, index) => {
    const verdict = verdicts[index]
    return verdict?.status === "solved" && verdict.keys === job.keys.length
      ? []
      : [`${job.level_id}: ${JSON.stringify(verdict)}`]
  })
  for (const failure of failures.slice(0, 10)) {
    console.log(`  ${failure}`)
  }
  return check(
    `${jobs.length - failures.length}/${jobs.length} solutions verified as the replay user`,
    failures.length === 0,
    seconds(started),
  )
}

async function checkHostile(sandbox: Sandbox, level: Level): Promise<boolean> {
  const jobs = await Promise.all(
    HOSTILE.map(({ notation }) => jobFor(level, splitNotation(notation + SOLVE))),
  )
  const garbage = await jobFor(
    level,
    splitNotation(':lua io.stdout:write("garbage on the pipe"); io.stdout:flush()<CR>'),
  )
  const [garbageVerdict, afterGarbage] = await runJobs(sandbox, [
    garbage,
    await jobFor(level, splitNotation(SOLVE)),
  ])
  const verdicts = await runJobs(sandbox, jobs)
  const results = [
    check(
      "garbage on the reply pipe only costs its own job",
      garbageVerdict?.status !== "solved" && afterGarbage?.status === "solved",
      `${garbageVerdict?.status}, then ${afterGarbage?.status}`,
    ),
    check(
      "every hostile log still replays to a verdict",
      verdicts.every((v) => v.status === "solved"),
      JSON.stringify(verdicts.map((v) => v.status)),
    ),
  ]
  const uid = await shell(sandbox, "cat /tmp/hostile-uid")
  const replayUid = await shell(sandbox, `id -u ${SANDBOX_PATHS.replayUser}`)
  results.push(check("replays don't run as root", uid === replayUid && uid !== "0", `uid ${uid}`))
  // Every check needs evidence the attempt ran: an empty result proves nothing.
  const jobsRead = await shell(sandbox, "cat /tmp/hostile-jobs")
  results.push(
    check(
      "the jobs file can't be read",
      jobsRead.includes("Permission denied") && !jobsRead.includes("level_hash"),
      jobsRead.slice(0, 80),
    ),
  )
  const write = await shell(sandbox, "cat /tmp/hostile-write")
  const tail = await shell(sandbox, `tail -c 20 ${SANDBOX_PATHS.cli}`)
  results.push(
    check(
      "the harness can't be changed",
      write !== "" && write !== "0" && !tail.includes("pwned"),
      `exit ${write}`,
    ),
  )
  const net = await shell(sandbox, "cat /tmp/hostile-net")
  const netExit = net.split("\n").at(-1) ?? ""
  results.push(
    check("the network is unreachable", netExit !== "" && netExit !== "0", net.slice(0, 70)),
  )
  const kill = await shell(sandbox, "cat /tmp/hostile-kill")
  results.push(check("the harness can't be killed", kill !== "" && kill !== "0", `exit ${kill}`))
  const left = await shell(sandbox, `pgrep -u ${SANDBOX_PATHS.replayUser} -c || true`)
  results.push(check("nothing is left running", left === "0", `${left} processes`))
  const homes = await shell(sandbox, "ls -d /tmp/vimdojo-replay-* 2>/dev/null | wc -l")
  results.push(check("nothing is left in its directory", homes === "0", `${homes} directories`))
  return results.every(Boolean)
}

async function checkForgery(sandbox: Sandbox, level: Level): Promise<boolean> {
  const verdicts = await runJobs(sandbox, [
    { level_id: level.id, level_hash: "sha256:not-this-level", keys: ["j"] },
    { level_id: "no-such-level", level_hash: "x", keys: ["j"] },
    await jobFor(level, ["j"]),
  ])
  return check(
    "wrong hash and unknown level are errors, and a short log is unsolved",
    verdicts[0]?.status === "error" &&
      verdicts[1]?.status === "error" &&
      verdicts[2]?.status === "unsolved",
    JSON.stringify(verdicts.map((v) => v.status)),
  )
}

async function main(): Promise<void> {
  const packs = readPacks(`${ROOT}challenges`)
  const levels = packs
    .filter((pack) => RANKED_TRACKS.has(pack.track))
    .flatMap((pack) => pack.levels)
  const hostileLevel = levels.find((level) => level.id === HOSTILE_LEVEL)
  if (hostileLevel === undefined) {
    throw new Error(`no level ${HOSTILE_LEVEL}`)
  }
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
    const results = [
      await checkSolutions(sandbox, levels),
      await checkHostile(sandbox, hostileLevel),
      await checkForgery(sandbox, hostileLevel),
    ]
    process.exitCode = results.every(Boolean) ? 0 : 1
  } finally {
    await sandbox.stop()
  }
  console.log(`total ${seconds(started)}`)
}

await main()
