// M15 acceptance check: every Motions and Usage reference solution must
// replay in the verifier with exactly its own key count, within par. A
// mismatch is a place where the verifier and the live room disagree.
//
// Usage: node dist/check-solutions.js [nvim]
import { availableParallelism } from "node:os"
import { fileURLToPath } from "node:url"
import type { Level } from "../../web/src/challenges"
import { splitNotation } from "../../web/src/keys"
import { readPacks } from "./packs"
import { replay, type Verdict } from "./replay"

const ROOT = fileURLToPath(new URL("../..", import.meta.url))
const RANKED_TRACKS: ReadonlySet<string> = new Set(["motions", "usage"])
// Matches the per-job limit the verifier will use in production (PLAN-v3).
const TIMEOUT_MS = 10_000

type Outcome = {
  readonly level: Level
  readonly expected: number
  readonly verdict: Verdict
  readonly ms: number
}

function describe({ level, expected, verdict }: Outcome): string | undefined {
  if (verdict.status !== "solved") {
    return verdict.status === "error" ? `error: ${verdict.reason}` : "did not solve"
  }
  if (verdict.keys !== expected) {
    return `solved in ${verdict.keys} keys, expected ${expected}`
  }
  if (verdict.keys > level.par_keys) {
    return `solved in ${verdict.keys} keys, over par ${level.par_keys}`
  }
  return undefined
}

async function main(): Promise<void> {
  const nvim = process.argv[2] ?? "nvim"
  const levels = readPacks(`${ROOT}challenges`)
    .filter((pack) => RANKED_TRACKS.has(pack.track))
    .flatMap((pack) => pack.levels)
  const queue = [...levels]
  const outcomes: Outcome[] = []
  const worker = async (): Promise<void> => {
    for (let level = queue.shift(); level !== undefined; level = queue.shift()) {
      const keys = splitNotation(level.solution)
      const started = performance.now()
      const verdict = await replay(
        { level, keys },
        { nvim, pluginDir: ROOT, timeoutMs: TIMEOUT_MS },
      )
      outcomes.push({ level, expected: keys.length, verdict, ms: performance.now() - started })
    }
  }
  const started = performance.now()
  await Promise.all(Array.from({ length: Math.min(availableParallelism(), 8) }, worker))
  const failures = outcomes.flatMap((outcome) => {
    const problem = describe(outcome)
    return problem === undefined ? [] : [`${outcome.level.id}: ${problem}`]
  })
  const times = outcomes.map((o) => o.ms).sort((a, b) => a - b)
  const median = times[Math.floor(times.length / 2)] ?? 0
  console.log(
    `${outcomes.length - failures.length}/${outcomes.length} reference solutions verified ` +
      `(median ${median.toFixed(0)} ms per replay, ${((performance.now() - started) / 1000).toFixed(1)} s total)`,
  )
  for (const failure of failures) {
    console.log(`  ✗ ${failure}`)
  }
  process.exitCode = failures.length === 0 ? 0 : 1
}

await main()
