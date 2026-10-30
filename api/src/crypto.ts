// Opaque random tokens and their hashes. Web Crypto, so this runs on Workers.

const TOKEN_PREFIX = "vdj_"
/** 256 bits, far beyond guessing, so a plain SHA-256 of a token is safe to store. */
const TOKEN_BYTES = 32
const ID_BYTES = 16

function toBase64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "")
}

function randomBytes(length: number): Uint8Array {
  return crypto.getRandomValues(new Uint8Array(length))
}

/** A random id for rows. Never derived from GitHub ids, so it reveals nothing. */
export function randomId(): string {
  return toBase64Url(randomBytes(ID_BYTES))
}

/** The prefix makes a leaked token easy to spot in dotfiles and secret scanners. */
export function newToken(): string {
  return `${TOKEN_PREFIX}${toBase64Url(randomBytes(TOKEN_BYTES))}`
}

export function randomUrlSafe(): string {
  return toBase64Url(randomBytes(TOKEN_BYTES))
}

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("")
}

/** The PKCE code challenge for a verifier (RFC 7636, S256). */
export async function pkceChallenge(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier))
  return toBase64Url(new Uint8Array(digest))
}
