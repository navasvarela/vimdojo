// M16 acceptance check: logs the plugin really writes must verify. Plays every
// ranked level through the live room, then replays each key log in the harness
// and compares the verifier's count with the count the player's game claimed.
// Also pins the log to the manifest: a hash the server wouldn't recognise fails.
//
// Usage: node dist/check-keylogs.js [nvim]
import { execFileSync } from "node:child_process"
import { mkdtempSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { fileURLToPath } from "node:url"
import { z } from "zod"
import { levelHash } from "../../web/src/level-hash"
import { readPacks } from "./packs"
import { replay } from "./replay"

const ROOT = fileURLToPath(new URL("../..", import.meta.url))
const TIMEOUT_MS = 10_000

const Run = z.object({
  level_id: z.string(),
  level_hash: z.string(),
  keys: z.array(z.string()),
  deltas_ms: z.array(z.number().int().nonnegative()),
  claimed: z.object({ keys: z.number().int() }),
})

const Manifest = z.object({
  levels: z.record(z.string(), z.object({ hash: z.string(), ranked: z.boolean() })),
})

function playSolutions(nvim: string, dir: string): void {
  execFileSync(
    nvim,
    [
      "--headless",
      "--noplugin",
      "-u",
      "tests/minimal_init.lua",
      "-c",
      "luafile verifier/play-solutions.lua",
    ],
    { cwd: ROOT, env: { ...process.env, VIMDOJO_KEYLOG_DIR: dir }, stdio: "inherit" },
  )
}

async function main(): Promise<void> {
  const nvim = process.argv[2] ?? "nvim"
  const manifest = Manifest.parse(
    JSON.parse(readFileSync(`${ROOT}verifier/manifest.json`, "utf8")),
  ).levels
  const levels = readPacks(`${ROOT}challenges`)
    .flatMap((pack) => pack.levels)
    .filter((level) => manifest[level.id]?.ranked === true)
  const dir = mkdtempSync(join(tmpdir(), "vimdojo-keylogs-"))
  const failures: string[] = []
  try {
    playSolutions(nvim, dir)
    for (const level of levels) {
      const run = Run.parse(JSON.parse(readFileSync(join(dir, `${level.id}.json`), "utf8")))
      const verdict = await replay(
        { level, keys: run.keys },
        { nvim, pluginDir: ROOT, timeoutMs: TIMEOUT_MS },
      )
      if (verdict.status !== "solved" || verdict.keys !== run.claimed.keys) {
        failures.push(
          `${level.id}: claimed ${run.claimed.keys}, verifier says ${JSON.stringify(verdict)}; keys ${run.keys.join(" ")}`,
        )
      }
      if (
        run.level_hash !== manifest[level.id]?.hash ||
        run.level_hash !== (await levelHash(level))
      ) {
        failures.push(`${level.id}: hash ${run.level_hash} isn't the manifest's`)
      }
      if (run.deltas_ms.length !== run.keys.length) {
        failures.push(`${level.id}: ${run.deltas_ms.length} gaps for ${run.keys.length} keys`)
      }
    }
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
  console.log(`${levels.length - failures.length}/${levels.length} key logs verified`)
  for (const failure of failures) {
    console.log(`  ✗ ${failure}`)
  }
  process.exitCode = failures.length === 0 ? 0 : 1
}

await main()
