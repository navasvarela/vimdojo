// Key counting rules shared with lua/vimdojo/keys.lua: one physical key is one
// keystroke, and "<Esc>"-style names count as a single key.

// <Esc>, <C-r>... plus a modifier with a punctuation key: <C-^>, <C-]>.
const SPECIAL_KEY = /^<[\w-]+>|^<[A-Za-z]-[^\w>]>/

/** Splits Vim key notation ("ciwfoo<Esc>") into one entry per key. */
export function splitNotation(notation: string): string[] {
  const keys: string[] = []
  let rest = notation
  while (rest.length > 0) {
    const special = SPECIAL_KEY.exec(rest)
    const key = special?.[0] ?? Array.from(rest)[0] ?? rest
    keys.push(key)
    rest = rest.slice(key.length)
  }
  return keys
}

const MODIFIER_KEYS: ReadonlySet<string> = new Set([
  "Shift",
  "Control",
  "Alt",
  "Meta",
  "CapsLock",
  "AltGraph",
  "Fn",
  "OS",
  "Dead",
  "Unidentified",
])

export type KeyEventLike = { readonly key: string }

/**
 * Whether a keydown is a key the player pressed (as opposed to holding a
 * modifier). Shift+4 arrives as one "$" keydown plus a "Shift" keydown, so
 * ignoring modifiers matches Neovim's count of one key.
 */
export function isCountableKeydown(event: KeyEventLike): boolean {
  // Synthetic events (automation, some IMEs) can arrive with an empty key.
  return event.key !== "" && !MODIFIER_KEYS.has(event.key)
}

const LINE_BREAK = /\r\n|\r/g

/**
 * The keys pasted (or dropped) text would have cost if typed, matching
 * `paste_count` in keys.lua: one per character, one `<CR>` per line break.
 */
export function pastedKeyCount(text: string): number {
  return Array.from(text.replace(LINE_BREAK, "\n")).length
}
