// Submitting a web run: the demo's keys go to the same endpoint the plugin uses, and
// the server replays them in Neovim, so web and plugin players share one board.
// Responses are checked at this edge, so the demo can trust them.
import { z } from "zod"
import { apiOrigin } from "../account/api"
import type { KeyLog } from "./session"

/** Stored with the run where the plugin stores its Neovim version. */
export const WEB_CLIENT = "web"

/** The same wait as the plugin's (online.lua): a few seconds, or the API's cron. */
export const VERIFY_POLL_MS = 3000
export const VERIFY_POLL_TRIES = 60

const RunStatus = z.enum([
  "pending",
  "verified",
  "mismatch",
  "rejected",
  "failed",
  "unranked",
  "not_best",
])
export type RunStatus = z.infer<typeof RunStatus>

const Submitted = z.object({ id: z.string(), status: RunStatus })
export type Submitted = z.infer<typeof Submitted>

const Run = z.object({
  id: z.string(),
  level_id: z.string(),
  status: RunStatus,
  claimed_keys: z.number(),
  verified_keys: z.number().nullable(),
})
export type Run = z.infer<typeof Run>

const ErrorBody = z.object({ message: z.string() })

export type WebRun = {
  readonly level_id: string
  readonly level_hash: string
  readonly log: KeyLog
  readonly claimed: { readonly keys: number; readonly seconds: number; readonly hinted: boolean }
}

const HTTP_OK = 200
const HTTP_UNAUTHORIZED = 401
const NETWORK_FAILURE = "Couldn't reach the server. Check your connection and try again."

/** A request the API refused, or that never arrived. Its message is for the player. */
export class RunError extends Error {}

type Fetch = typeof fetch

export class RunsApi {
  constructor(private readonly fetcher: Fetch = (...args) => fetch(...args)) {}

  private async send(method: string, path: string, body?: unknown): Promise<Response> {
    try {
      return await this.fetcher(`${apiOrigin()}/api/v1${path}`, {
        method,
        credentials: "include",
        ...(body === undefined
          ? {}
          : { headers: { "content-type": "application/json" }, body: JSON.stringify(body) }),
      })
    } catch {
      throw new RunError(NETWORK_FAILURE)
    }
  }

  private async refusal(response: Response): Promise<RunError> {
    if (response.status === HTTP_UNAUTHORIZED) {
      return new RunError("Your sign-in has expired. Sign in again on your account page.")
    }
    const parsed = ErrorBody.safeParse(await response.json().catch(() => undefined))
    return new RunError(
      parsed.success ? parsed.data.message : `The server said ${response.status}.`,
    )
  }

  /** @returns undefined when the server can't be asked, so the demo offers nothing. */
  async signedIn(): Promise<boolean | undefined> {
    try {
      const response = await this.send("GET", "/me")
      if (response.status === HTTP_OK) {
        return true
      }
      return response.status === HTTP_UNAUTHORIZED ? false : undefined
    } catch {
      return undefined
    }
  }

  async submit(run: WebRun): Promise<Submitted> {
    const response = await this.send("POST", "/runs", {
      level_id: run.level_id,
      level_hash: run.level_hash,
      nvim: WEB_CLIENT,
      keys: run.log.keys,
      deltas_ms: run.log.deltas_ms,
      claimed: run.claimed,
    })
    if (!response.ok) {
      throw await this.refusal(response)
    }
    return Submitted.parse(await response.json())
  }

  async run(id: string): Promise<Run> {
    const response = await this.send("GET", `/runs/${encodeURIComponent(id)}`)
    if (!response.ok) {
      throw await this.refusal(response)
    }
    return Run.parse(await response.json())
  }
}

/** The verdict in words, as online.lua words it. Undefined while it's still pending. */
export function verdictText(run: Run): string | undefined {
  switch (run.status) {
    case "pending":
      return undefined
    case "verified":
      return `Verified: ${run.verified_keys ?? run.claimed_keys} keys.`
    case "mismatch":
      return `Verified at ${run.verified_keys ?? "?"} keys (the demo counted ${run.claimed_keys}).`
    case "rejected":
      return "Real Neovim didn't solve the level with these keys, so this run isn't ranked. The demo's Vim emulation sometimes differs from Neovim."
    case "failed":
      return "This run couldn't be verified. Try again later."
    case "unranked":
      return "This level isn't ranked, so the run stays off the boards."
    case "not_best":
      return "This run doesn't beat your verified best."
  }
}
