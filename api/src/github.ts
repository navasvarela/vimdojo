// The parts of GitHub's OAuth the API uses. Only the numeric user id is kept;
// access tokens and the rest of the profile are dropped straight away.
import { z } from "zod"
import { ApiError, Status } from "./http"

const LOGIN_ORIGIN = "https://github.com"
const API_ORIGIN = "https://api.github.com"
// GitHub rejects API requests without a User-Agent.
const USER_AGENT = "vimdojo-api"

export type DeviceStart = {
  readonly deviceCode: string
  readonly userCode: string
  readonly verificationUri: string
  readonly expiresInSeconds: number
  readonly intervalSeconds: number
}

export type DevicePoll =
  | { readonly status: "pending"; readonly intervalSeconds: number | undefined }
  | { readonly status: "failed" }
  | { readonly status: "authorized"; readonly accessToken: string }

/** An interface so tests can stand in for GitHub. */
export type GitHub = {
  readonly startDevice: () => Promise<DeviceStart>
  readonly pollDevice: (deviceCode: string) => Promise<DevicePoll>
  readonly exchangeCode: (code: string, verifier: string, redirectUri: string) => Promise<string>
  readonly userId: (accessToken: string) => Promise<number>
}

export type GitHubCredentials = {
  readonly clientId: string
  readonly clientSecret: string
}

const DeviceCodeResponse = z.object({
  device_code: z.string(),
  user_code: z.string(),
  verification_uri: z.string(),
  expires_in: z.number(),
  interval: z.number(),
})

// GitHub reports these with HTTP 200, as an `error` field.
const TokenResponse = z.object({
  access_token: z.string().optional(),
  error: z.string().optional(),
  interval: z.number().optional(),
})

const UserResponse = z.object({ id: z.number().int() })

const PENDING_ERRORS: ReadonlySet<string> = new Set(["authorization_pending", "slow_down"])

function upstreamError(): ApiError {
  return new ApiError(Status.BadGateway, "github_unavailable", "GitHub didn't answer as expected.")
}

async function readJson<T>(response: Response, schema: z.ZodType<T>): Promise<T> {
  const parsed = schema.safeParse(response.ok ? await response.json() : undefined)
  if (!parsed.success) {
    throw upstreamError()
  }
  return parsed.data
}

function postForm(path: string, form: Record<string, string>): Promise<Response> {
  return fetch(`${LOGIN_ORIGIN}${path}`, {
    method: "POST",
    headers: { accept: "application/json", "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(form),
  })
}

export function realGitHub({ clientId, clientSecret }: GitHubCredentials): GitHub {
  return {
    async startDevice() {
      // No scope: that grants read access to public profile data only.
      const response = await postForm("/login/device/code", { client_id: clientId })
      const data = await readJson(response, DeviceCodeResponse)
      return {
        deviceCode: data.device_code,
        userCode: data.user_code,
        verificationUri: data.verification_uri,
        expiresInSeconds: data.expires_in,
        intervalSeconds: data.interval,
      }
    },

    async pollDevice(deviceCode) {
      const response = await postForm("/login/oauth/access_token", {
        client_id: clientId,
        device_code: deviceCode,
        grant_type: "urn:ietf:params:oauth:grant-type:device_code",
      })
      const data = await readJson(response, TokenResponse)
      if (data.access_token !== undefined) {
        return { status: "authorized", accessToken: data.access_token }
      }
      if (data.error !== undefined && PENDING_ERRORS.has(data.error)) {
        return { status: "pending", intervalSeconds: data.interval }
      }
      return { status: "failed" }
    },

    async exchangeCode(code, verifier, redirectUri) {
      const response = await postForm("/login/oauth/access_token", {
        client_id: clientId,
        client_secret: clientSecret,
        code,
        code_verifier: verifier,
        redirect_uri: redirectUri,
      })
      const data = await readJson(response, TokenResponse)
      if (data.access_token === undefined) {
        throw new ApiError(Status.BadRequest, "login_failed", "GitHub refused the login.")
      }
      return data.access_token
    },

    async userId(accessToken) {
      const response = await fetch(`${API_ORIGIN}/user`, {
        headers: {
          accept: "application/vnd.github+json",
          authorization: `Bearer ${accessToken}`,
          "user-agent": USER_AGENT,
        },
      })
      return (await readJson(response, UserResponse)).id
    },
  }
}
