// The account page's calls to the API. Responses are checked at this edge, so
// the page itself can trust them.
import { z } from "zod"

const DEFAULT_API_ORIGIN = "https://api.vimdojo.org"

function apiOrigin(): string {
  const configured: unknown = import.meta.env["VITE_API_URL"]
  return typeof configured === "string" && configured !== "" ? configured : DEFAULT_API_ORIGIN
}

export const SIGN_IN_URL = `${apiOrigin()}/api/v1/auth/github/start`
export const DELETE_PHRASE = "delete my account"

const Me = z.object({
  handle: z.string().nullable(),
  handle_rules: z.string(),
  /** When the handle can next change; null when it can now. */
  handle_changes_at: z.string().nullable().default(null),
  /** Until when a new handle can change freely; null once that has passed. */
  handle_free_until: z.string().nullable().default(null),
})
export type Me = z.infer<typeof Me>

const Login = z.object({
  id: z.string(),
  kind: z.enum(["web", "plugin"]),
  created_at: z.string(),
  last_used_at: z.string(),
  current: z.boolean(),
})
export type Login = z.infer<typeof Login>

const Logins = z.object({ tokens: z.array(Login) })
const ErrorBody = z.object({ message: z.string() })

const HTTP_UNAUTHORIZED = 401
const NETWORK_FAILURE = "Couldn't reach the server. Check your connection and try again."

/** A request the API refused, or that never arrived. Its message is for the player. */
export class AccountError extends Error {}

type Fetch = typeof fetch

export class AccountApi {
  constructor(private readonly fetcher: Fetch = (...args) => fetch(...args)) {}

  private async send(method: string, path: string, body?: unknown): Promise<Response> {
    let response: Response
    try {
      response = await this.fetcher(`${apiOrigin()}/api/v1${path}`, {
        method,
        credentials: "include",
        ...(body === undefined
          ? {}
          : { headers: { "content-type": "application/json" }, body: JSON.stringify(body) }),
      })
    } catch {
      throw new AccountError(NETWORK_FAILURE)
    }
    if (!response.ok && response.status !== HTTP_UNAUTHORIZED) {
      const parsed = ErrorBody.safeParse(await response.json().catch(() => undefined))
      throw new AccountError(parsed.success ? parsed.data.message : "Something went wrong.")
    }
    return response
  }

  /** @returns undefined when nobody is signed in. */
  async me(): Promise<Me | undefined> {
    const response = await this.send("GET", "/me")
    return response.status === HTTP_UNAUTHORIZED ? undefined : Me.parse(await response.json())
  }

  async setHandle(handle: string): Promise<void> {
    await this.send("PATCH", "/me", { handle })
  }

  async logins(): Promise<readonly Login[]> {
    return Logins.parse(await (await this.send("GET", "/me/tokens")).json()).tokens
  }

  async revoke(id: string): Promise<void> {
    await this.send("DELETE", `/me/tokens/${encodeURIComponent(id)}`)
  }

  async exportData(): Promise<string> {
    return (await this.send("GET", "/me/export")).text()
  }

  async signOut(): Promise<void> {
    await this.send("POST", "/auth/logout", {})
  }

  async deleteAccount(): Promise<void> {
    await this.send("DELETE", "/me", { confirm: DELETE_PHRASE })
  }
}
