/** What the Worker gets from Cloudflare: bindings, vars and secrets. */
export type Env = {
  readonly DB: D1Database
  /** The site's origin, the only one allowed to call with cookies. */
  readonly SITE_ORIGIN: string
  /** This API's own origin, for the OAuth redirect. */
  readonly API_ORIGIN: string
  readonly GITHUB_CLIENT_ID: string
  readonly GITHUB_CLIENT_SECRET: string
  /** Mixed into IP hashes so they can't be reversed by trying every address. */
  readonly RATE_LIMIT_SALT: string
}

export const MINUTE_MS = 60_000
export const DAY_MS = 24 * 60 * MINUTE_MS

/** Sessions and plugin tokens slide: each use extends them by this much. */
export const TOKEN_LIFETIME_MS = 30 * DAY_MS
/** Only refresh a token's dates this often, to keep D1 writes (100k a day) low. */
export const TOKEN_TOUCH_INTERVAL_MS = DAY_MS
export const HANDLE_CHANGE_INTERVAL_MS = 30 * DAY_MS
/** A new handle can change freely for this long, so a typo at sign-up can be fixed. */
export const HANDLE_FREE_WINDOW_MS = DAY_MS
export const HANDLE_HOLD_MS = 90 * DAY_MS
/** Bodies are small JSON objects; anything bigger is refused unread. */
export const MAX_BODY_BYTES = 16 * 1024
/** How long a browser has to finish signing in on GitHub. */
export const OAUTH_COOKIE_SECONDS = 600
