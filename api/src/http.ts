// Small HTTP helpers: errors, JSON, cookies, body parsing and CORS.
import type { z } from "zod"
import { MAX_BODY_BYTES } from "./config"

/** An error the client is meant to see. Anything else becomes a bare 500. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message)
  }
}

export const Status = {
  Ok: 200,
  Accepted: 202,
  NoContent: 204,
  Found: 302,
  BadRequest: 400,
  Unauthorized: 401,
  Forbidden: 403,
  NotFound: 404,
  Conflict: 409,
  PayloadTooLarge: 413,
  UnsupportedMediaType: 415,
  UnprocessableEntity: 422,
  TooManyRequests: 429,
  InternalServerError: 500,
  BadGateway: 502,
} as const

export function json(data: unknown, status: number = Status.Ok): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  })
}

export function errorResponse(error: ApiError): Response {
  return json({ error: error.code, message: error.message }, error.status)
}

export function noContent(): Response {
  return new Response(null, { status: Status.NoContent })
}

export function redirect(location: string): Response {
  return new Response(null, { status: Status.Found, headers: { location } })
}

export function cookieValue(request: Request, name: string): string | undefined {
  for (const part of (request.headers.get("cookie") ?? "").split(";")) {
    const separator = part.indexOf("=")
    if (separator !== -1 && part.slice(0, separator).trim() === name) {
      return part.slice(separator + 1).trim()
    }
  }
  return undefined
}

/** `__Host-` makes browsers insist on Secure, Path=/ and no Domain attribute. */
export function hostCookie(name: string, value: string, maxAgeSeconds: number): string {
  return `${name}=${value}; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=${maxAgeSeconds}`
}

/**
 * Reads a JSON body. Requiring the JSON content type also protects cookie
 * sessions: a cross-site form can't send it without a CORS preflight.
 */
export async function parseBody<T>(request: Request, schema: z.ZodType<T>): Promise<T> {
  if (!(request.headers.get("content-type") ?? "").startsWith("application/json")) {
    throw new ApiError(Status.UnsupportedMediaType, "json_required", "Send a JSON body.")
  }
  const text = await request.text()
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) {
    throw new ApiError(Status.PayloadTooLarge, "too_large", "The body is too large.")
  }
  let value: unknown
  try {
    value = JSON.parse(text)
  } catch {
    throw new ApiError(Status.BadRequest, "invalid_json", "The body isn't valid JSON.")
  }
  const parsed = schema.safeParse(value)
  if (!parsed.success) {
    throw new ApiError(Status.UnprocessableEntity, "invalid_body", "The body has the wrong shape.")
  }
  return parsed.data
}

const ALLOWED_METHODS = "GET, POST, PATCH, DELETE, OPTIONS"
const PREFLIGHT_MAX_AGE_SECONDS = "86400"
const HSTS_MAX_AGE_SECONDS = 31_536_000

export function preflight(request: Request, siteOrigin: string): Response {
  const allowed = request.headers.get("origin") === siteOrigin
  return new Response(null, {
    status: Status.NoContent,
    headers: allowed
      ? {
          "access-control-allow-methods": ALLOWED_METHODS,
          "access-control-allow-headers": "content-type",
          "access-control-max-age": PREFLIGHT_MAX_AGE_SECONDS,
        }
      : {},
  })
}

/** How long the CDN and browsers can reuse a public response. Boards can lag this much. */
const PUBLIC_MAX_AGE_SECONDS = 60

/** Boards and profiles: readable from anywhere, and the same for everyone. */
export function withPublicHeaders(response: Response): Response {
  const result = new Response(response.body, response)
  result.headers.set("strict-transport-security", `max-age=${HSTS_MAX_AGE_SECONDS}`)
  result.headers.set("x-content-type-options", "nosniff")
  result.headers.set("cache-control", `public, max-age=${PUBLIC_MAX_AGE_SECONDS}`)
  result.headers.set("access-control-allow-origin", "*")
  return result
}

/** Only the site's own origin may read responses, or send its cookies. */
export function withStandardHeaders(
  response: Response,
  request: Request,
  siteOrigin: string,
): Response {
  const result = new Response(response.body, response)
  result.headers.set("strict-transport-security", `max-age=${HSTS_MAX_AGE_SECONDS}`)
  result.headers.set("x-content-type-options", "nosniff")
  result.headers.set("cache-control", "no-store")
  result.headers.append("vary", "origin")
  if (request.headers.get("origin") === siteOrigin) {
    result.headers.set("access-control-allow-origin", siteOrigin)
    result.headers.set("access-control-allow-credentials", "true")
  }
  return result
}
