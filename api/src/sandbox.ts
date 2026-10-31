// Runs a batch in a Vercel Sandbox resumed from the verifier snapshot, with no
// network. Jobs hold only levels and keys: no user id, handle or token.
import { z } from "zod"
import { REGION, SANDBOX_PATHS } from "../../verifier/sandbox/config"
import { BadBatchError, type VerifierRunner } from "./verify"

const JOBS_PATH = "jobs.json"
// Ten jobs at 10 s each, the most a batch can take, plus starting up.
const BATCH_TIMEOUT_MS = 120_000

export type SandboxCredentials = {
  readonly token: string
  readonly teamId: string
  readonly projectId: string
  readonly snapshotId: string
}

const Verdicts = z.array(
  z.discriminatedUnion("status", [
    z.object({ status: z.literal("solved"), keys: z.number().int().positive() }),
    z.object({ status: z.literal("unsolved") }),
    z.object({ status: z.literal("error"), reason: z.string() }),
  ]),
)

function parseVerdicts(stdout: string, exitCode: number): z.infer<typeof Verdicts> {
  if (exitCode !== 0) {
    throw new BadBatchError(`the harness exited with ${exitCode}`)
  }
  try {
    return Verdicts.parse(JSON.parse(stdout))
  } catch {
    throw new BadBatchError("the harness's output wasn't a list of verdicts")
  }
}

export function sandboxRunner(credentials: SandboxCredentials): VerifierRunner {
  return async (jobs) => {
    // Imported here so ordinary API requests never pay to load the SDK.
    const { Sandbox } = await import("@vercel/sandbox")
    const sandbox = await Sandbox.create({
      token: credentials.token,
      teamId: credentials.teamId,
      projectId: credentials.projectId,
      source: { type: "snapshot", snapshotId: credentials.snapshotId },
      region: REGION,
      networkPolicy: "deny-all",
      resources: { vcpus: 1 },
      timeout: BATCH_TIMEOUT_MS,
    })
    try {
      await sandbox.writeFiles([{ path: JOBS_PATH, content: Buffer.from(JSON.stringify(jobs)) }])
      await sandbox.runCommand({
        cmd: "sh",
        args: ["-c", `chown root:root ${JOBS_PATH} && chmod 600 ${JOBS_PATH}`],
        sudo: true,
      })
      // The harness runs as root, and each replay as an unprivileged user, so a
      // key log can't touch the harness that decides its verdict.
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
        timeoutMs: BATCH_TIMEOUT_MS,
      })
      return parseVerdicts(await result.stdout(), result.exitCode)
    } finally {
      await sandbox.stop()
    }
  }
}
