// M15 spike: a Worker that runs one verification batch in a Vercel Sandbox
// resumed from the verifier snapshot, with the network denied, and reports
// timings. It answers only POST /spike with the SPIKE_SECRET bearer token.
import { Sandbox } from "@vercel/sandbox"
import basicMotions from "../../challenges/01-basic-motions.json"
import project from "../../challenges/11-project-wide.json"
import { parsePacks } from "../../web/src/challenges"
import { splitNotation } from "../../web/src/keys"
import { REGION, SANDBOX_PATHS } from "../../verifier/sandbox/config"

type Env = {
  readonly VERCEL_TOKEN: string
  readonly VERCEL_TEAM_ID: string
  readonly VERCEL_PROJECT_ID: string
  readonly VERIFIER_SNAPSHOT_ID: string
  readonly SPIKE_SECRET: string
}

const JOBS_PATH = "jobs.json"
const BATCH_TIMEOUT_MS = 60_000

function jobs() {
  return parsePacks([basicMotions, project])
    .flatMap((pack) => pack.levels)
    .map((level) => ({ level, keys: splitNotation(level.solution) }))
}

async function runBatch(env: Env): Promise<Record<string, unknown>> {
  const started = Date.now()
  const sandbox = await Sandbox.create({
    token: env.VERCEL_TOKEN,
    teamId: env.VERCEL_TEAM_ID,
    projectId: env.VERCEL_PROJECT_ID,
    source: { type: "snapshot", snapshotId: env.VERIFIER_SNAPSHOT_ID },
    region: REGION,
    networkPolicy: "deny-all",
    resources: { vcpus: 1 },
    timeout: BATCH_TIMEOUT_MS,
  })
  const ready = Date.now()
  try {
    const batch = jobs()
    await sandbox.writeFiles([{ path: JOBS_PATH, content: Buffer.from(JSON.stringify(batch)) }])
    const result = await sandbox.runCommand({
      cmd: "node",
      args: [SANDBOX_PATHS.cli, SANDBOX_PATHS.plugin, SANDBOX_PATHS.nvim, JOBS_PATH],
    })
    const verdicts: unknown = JSON.parse(await result.stdout())
    return {
      jobs: batch.map((job) => ({ id: job.level.id, keys: job.keys.length })),
      verdicts,
      exitCode: result.exitCode,
      ms: { create: ready - started, replay: Date.now() - ready, total: Date.now() - started },
    }
  } finally {
    await sandbox.stop()
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url)
    if (request.method !== "POST" || url.pathname !== "/spike") {
      return new Response("not found", { status: 404 })
    }
    if (
      env.SPIKE_SECRET === "" ||
      request.headers.get("authorization") !== `Bearer ${env.SPIKE_SECRET}`
    ) {
      return new Response("unauthorized", { status: 401 })
    }
    try {
      return Response.json(await runBatch(env))
    } catch (error) {
      if (error instanceof Error) {
        console.error("runBatch failed:", error.stack ?? `${error.name}: ${error.message}`)
      } else {
        console.error("runBatch failed:", String(error))
      }
      return new Response("internal server error", { status: 500 })
    }
  },
} satisfies ExportedHandler<Env>
