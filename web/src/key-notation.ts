// Names a browser keydown the way the plugin's key logs name a key: Neovim's
// keytrans() spelling, as keys.lua's `name` normalizes it. A web run is replayed in
// Neovim from these names, and the server caches verdicts by log, so the same keys
// must get the same names from either client. tests/fixtures/key_notation.json pins
// the mapping, and tests/key_notation_spec.lua checks every name against keytrans().

export type KeyPress = {
  readonly key: string
  readonly ctrlKey: boolean
  readonly altKey: boolean
  readonly metaKey: boolean
  readonly shiftKey: boolean
}

const NAMED_KEYS: Readonly<Record<string, string>> = {
  Escape: "Esc",
  Enter: "CR",
  Backspace: "BS",
  Tab: "Tab",
  Delete: "Del",
  Insert: "Insert",
  ArrowUp: "Up",
  ArrowDown: "Down",
  ArrowLeft: "Left",
  ArrowRight: "Right",
  Home: "Home",
  End: "End",
  PageUp: "PageUp",
  PageDown: "PageDown",
}

// Shift changes these in a terminal, so keytrans() names it. Elsewhere it's in the
// character: Shift+a arrives as "A".
const SHIFTABLE: ReadonlySet<string> = new Set(["Tab", "Up", "Down", "Left", "Right"])

// What a terminal sends for these Ctrl chords is an ASCII control character that
// keytrans() names after the key it duplicates: Ctrl+I is a Tab.
const CTRL_ALIASES: Readonly<Record<string, string>> = {
  i: "<Tab>",
  m: "<CR>",
  j: "<NL>",
  "[": "<Esc>",
}

const CTRL_PUNCTUATION: ReadonlySet<string> = new Set(["]", "^", "\\", "_"])

const LITERAL_NAMES: Readonly<Record<string, string>> = { " ": "<Space>", "<": "<lt>" }

const FUNCTION_KEY = /^F([1-9]|1[0-2])$/

function namedKey(press: KeyPress): string | undefined {
  const name = NAMED_KEYS[press.key] ?? (FUNCTION_KEY.test(press.key) ? press.key : undefined)
  if (name === undefined || press.ctrlKey) {
    return undefined
  }
  return press.shiftKey && SHIFTABLE.has(name) ? `<S-${name}>` : `<${name}>`
}

function ctrlChord(key: string): string | undefined {
  const lower = key.toLowerCase()
  const alias = CTRL_ALIASES[lower]
  if (alias !== undefined) {
    return alias
  }
  if (/^[a-z]$/.test(lower)) {
    return `<C-${lower.toUpperCase()}>`
  }
  return CTRL_PUNCTUATION.has(key) ? `<C-${key}>` : undefined
}

/**
 * The key's name, or undefined for one a key log can't hold: Alt and Cmd chords,
 * and keys this mapping doesn't know. The demo still counts the latter, so an
 * attempt with one can't be submitted.
 */
export function keyNotation(press: KeyPress): string | undefined {
  if (press.metaKey || press.altKey) {
    return undefined
  }
  if (Array.from(press.key).length !== 1) {
    return namedKey(press)
  }
  if (press.ctrlKey) {
    return ctrlChord(press.key)
  }
  return LITERAL_NAMES[press.key] ?? press.key
}
