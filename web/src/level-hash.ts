// A level's identity on the leaderboards, ported from lua/vimdojo/level_hash.lua
// (see there for why these fields). tests/fixtures/level_hash.json pins both.
import type { Level } from "./challenges"

/**
 * Keys sort by UTF-16 code unit where the Lua port sorts by byte. The two
 * orders differ only for characters outside the Basic Multilingual Plane, which
 * no option name, register, mark or workspace path uses.
 */
function encode(value: unknown): string {
  if (typeof value === "string" || typeof value === "boolean") {
    return JSON.stringify(value)
  }
  if (typeof value === "number") {
    if (!Number.isInteger(value)) {
      throw new Error("level hash: non-integer number")
    }
    return String(value)
  }
  if (Array.isArray(value)) {
    return `[${value.map(encode).join(",")}]`
  }
  if (typeof value === "object" && value !== null) {
    const members = Object.entries(value)
      .filter(([, member]) => member !== undefined)
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([name, member]) => `${JSON.stringify(name)}:${encode(member)}`)
    return `{${members.join(",")}}`
  }
  throw new Error(`level hash: unsupported value of type ${typeof value}`)
}

export function canonicalLevel(level: Level): string {
  const workspace = level.files !== undefined
  return encode({
    cursor_start: level.cursor_start,
    files: level.files,
    goal: level.goal,
    open: workspace ? level.open : undefined,
    options: level.options,
    preset: level.preset,
    requires: level.requires,
    start_text: workspace ? undefined : level.start_text,
  })
}

/** "sha256:<hex>". Web Crypto, so the site, Node and Workers can all run it. */
export async function levelHash(level: Level): Promise<string> {
  const bytes = new TextEncoder().encode(canonicalLevel(level))
  const digest = await crypto.subtle.digest("SHA-256", bytes)
  const hex = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0"))
  return `sha256:${hex.join("")}`
}
