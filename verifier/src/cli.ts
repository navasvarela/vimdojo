// The verifier's entry point inside the sandbox: reads a JSON array of jobs
// ({ level, keys }) from a file and writes a JSON array of verdicts on
// stdout, in the same order. Jobs run one at a time, each in its own Neovim.
//
// Usage: node dist/cli.js <plugin-dir> <nvim> <jobs.json>
import { readFile } from "node:fs/promises"
import { parseLevel } from "./packs"
import { replay, type Verdict } from "./replay"

const TIMEOUT_MS = 10_000

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string")
}

async function runJob(raw: unknown, pluginDir: string, nvim: string): Promise<Verdict> {
  if (typeof raw !== "object" || raw === null || !("level" in raw) || !("keys" in raw)) {
    return { status: "error", reason: "a job needs a level and keys" }
  }
  if (!isStringArray(raw.keys)) {
    return { status: "error", reason: "keys must be an array of strings" }
  }
  try {
    return await replay(
      { level: parseLevel(raw.level), keys: raw.keys },
      { nvim, pluginDir, timeoutMs: TIMEOUT_MS },
    )
  } catch (error) {
    return { status: "error", reason: error instanceof Error ? error.message : String(error) }
  }
}

async function main(): Promise<void> {
  const [pluginDir, nvim, jobsFile] = process.argv.slice(2)
  if (pluginDir === undefined || nvim === undefined || jobsFile === undefined) {
    throw new Error("usage: cli.js <plugin-dir> <nvim> <jobs.json>")
  }
  const jobs: unknown = JSON.parse(await readFile(jobsFile, "utf8"))
  if (!Array.isArray(jobs)) {
    throw new Error("the jobs file must hold a JSON array of jobs")
  }
  const verdicts: Verdict[] = []
  for (const job of jobs) {
    verdicts.push(await runJob(job, pluginDir, nvim))
  }
  process.stdout.write(`${JSON.stringify(verdicts)}\n`)
}

await main()
