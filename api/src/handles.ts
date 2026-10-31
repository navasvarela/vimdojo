// Public handles: what a player is called on the boards.

const MIN_LENGTH = 3
const MAX_LENGTH = 20
const ALLOWED = /^[a-z0-9_-]+$/

// Names that could pass for the project or its staff. Offensive names are left
// to moderation: a word list is easy to get around and catches innocent handles.
const RESERVED: ReadonlySet<string> = new Set([
  "admin",
  "administrator",
  "anonymous",
  "api",
  "github",
  "maintainer",
  "mod",
  "moderator",
  "neovim",
  "nvim",
  "root",
  "staff",
  "support",
  "system",
  "vim",
  "vimdojo",
])

export type HandleProblem = "length" | "characters" | "reserved"

export function handleProblem(handle: string): HandleProblem | undefined {
  if (handle.length < MIN_LENGTH || handle.length > MAX_LENGTH) {
    return "length"
  }
  if (!ALLOWED.test(handle)) {
    return "characters"
  }
  return RESERVED.has(handle) ? "reserved" : undefined
}

export const HANDLE_RULES = `${MIN_LENGTH} to ${MAX_LENGTH} characters: lowercase letters, digits, _ and -`
