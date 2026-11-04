// Port of lua/vimdojo/tips.lua: one tip from the keys a player typed.
// tests/fixtures/tips.json pins both. See the Lua file for how keys are read.
import { splitNotation } from "../keys"

type CommandKind = "motion" | "insert" | "command_line"

type Command = {
  readonly count: string
  readonly keys: string
  readonly kind: CommandKind
  readonly entry?: string
  readonly text?: readonly string[]
  readonly operator?: string
  readonly motion?: string
}

type Tip = { readonly text: string; readonly saving: number }

const INSERT_ENTRIES: ReadonlySet<string> = new Set([
  "i",
  "a",
  "o",
  "I",
  "A",
  "O",
  "s",
  "S",
  "C",
  "R",
])
const OPERATORS: ReadonlySet<string> = new Set(["d", "y", "c", "<", ">", "="])
const G_OPERATORS: ReadonlySet<string> = new Set(["U", "u", "~", "?"])
const TAKES_ARGUMENT: ReadonlySet<string> = new Set([
  "f",
  "t",
  "F",
  "T",
  "r",
  "m",
  "'",
  "`",
  "@",
  "q",
  '"',
  "g",
  "z",
  "Z",
  "[",
  "]",
  "<C-W>",
])
const TEXT_OBJECT: ReadonlySet<string> = new Set(["i", "a"])
const COMMAND_LINES: ReadonlySet<string> = new Set([":", "/", "?"])
const ENDS_COMMAND_LINE: ReadonlySet<string> = new Set(["<CR>", "<Esc>"])
const ENDS_INSERT: ReadonlySet<string> = new Set(["<Esc>"])
const ARROWS: ReadonlySet<string> = new Set(["<Up>", "<Down>", "<Left>", "<Right>"])
const NOT_REPEATABLE: ReadonlySet<CommandKind> = new Set(["insert", "command_line"])
const PAIRS_TO_ONE: Readonly<Record<string, Readonly<Record<string, string>>>> = {
  x: { i: "s" },
  D: { a: "C" },
  "^": { i: "I" },
  $: { a: "A" },
}

const ARROW_TIP =
  "Arrow keys move your hand off the home row: `h` `j` `k` `l` do the same in Normal mode."

/** A count can't start with 0: on its own, `0` is the motion to the start of the line. */
function isCountDigit(key: string | undefined, first: boolean): boolean {
  return key !== undefined && /^\d$/.test(key) && !(first && key === "0")
}

/** @returns the text, and the position past the key that ended it. */
function untilEnd(
  keys: readonly string[],
  start: number,
  ends: ReadonlySet<string>,
): [string[], number] {
  const text: string[] = []
  let pos = start
  while (pos < keys.length && !ends.has(keys[pos] ?? "")) {
    text.push(keys[pos] ?? "")
    pos++
  }
  return [text, pos + 1]
}

/** A motion after an operator: `w`, `fx`, `iw`, `gg`, `$`. */
function readMotion(keys: readonly string[], pos: number): [string, number] {
  const key = keys[pos] ?? ""
  if (TAKES_ARGUMENT.has(key) || TEXT_OBJECT.has(key)) {
    return [key + (keys[pos + 1] ?? ""), pos + 2]
  }
  return [key, pos + 1]
}

export function commands(keys: readonly string[]): Command[] {
  const result: Command[] = []
  let pos = 0
  while (pos < keys.length) {
    let count = ""
    while (isCountDigit(keys[pos], count === "")) {
      count += keys[pos] ?? ""
      pos++
    }
    const key = keys[pos]
    if (key === undefined) {
      break
    }
    const next = keys[pos + 1] ?? ""
    if (INSERT_ENTRIES.has(key)) {
      const [text, after] = untilEnd(keys, pos + 1, ENDS_INSERT)
      result.push({ count, keys: key, kind: "insert", entry: key, text })
      pos = after
    } else if (COMMAND_LINES.has(key)) {
      const [text, after] = untilEnd(keys, pos + 1, ENDS_COMMAND_LINE)
      result.push({ count, keys: key, kind: "command_line", text })
      pos = after
    } else if (OPERATORS.has(key) || (key === "g" && G_OPERATORS.has(next))) {
      const operator = key === "g" ? key + next : key
      pos += key === "g" ? 2 : 1
      let motion: string
      if (keys[pos] === key) {
        motion = key
        pos++
      } else {
        ;[motion, pos] = readMotion(keys, pos)
      }
      if (operator === "c") {
        const [text, after] = untilEnd(keys, pos, ENDS_INSERT)
        result.push({
          count,
          keys: operator + motion,
          kind: "insert",
          entry: "c",
          text,
          operator,
          motion,
        })
        pos = after
      } else {
        result.push({ count, keys: operator + motion, kind: "motion", operator, motion })
      }
    } else if (TAKES_ARGUMENT.has(key)) {
      result.push({ count, keys: key + next, kind: "motion" })
      pos += 2
    } else {
      result.push({ count, keys: key, kind: "motion" })
      pos++
    }
  }
  return result
}

/** A run of the same command a count could replace: `jjjj` is `4j`. */
function repeatedRun(list: readonly Command[]): Tip | undefined {
  let best: Tip | undefined
  let i = 0
  while (i < list.length) {
    const command = list[i]
    if (command === undefined) {
      break
    }
    let j = i
    while (
      list[j + 1]?.keys === command.keys &&
      list[j + 1]?.count === "" &&
      list[j + 1]?.kind === command.kind
    ) {
      j++
    }
    const times = j - i + 1
    const length = splitNotation(command.keys).length
    const counted = String(times).length + length
    const saving = times * length - counted
    if (
      command.count === "" &&
      !NOT_REPEATABLE.has(command.kind) &&
      !ARROWS.has(command.keys) &&
      saving > 0 &&
      (best === undefined || saving > best.saving)
    ) {
      best = {
        saving,
        text: `You typed \`${command.keys}\` ${times} times in a row: \`${times}${command.keys}\` does the same in ${counted} keys.`,
      }
    }
    i = j + 1
  }
  return best
}

function shorterPair(before: Command, after: Command): string | undefined {
  if (after.kind !== "insert" || after.entry === undefined) {
    return undefined
  }
  if (before.operator === "d" && before.motion !== "d" && after.entry === "i") {
    return `${before.count}c${before.motion ?? ""}`
  }
  const shorter = PAIRS_TO_ONE[before.keys]?.[after.entry]
  return shorter !== undefined && before.count === "" ? shorter : undefined
}

/** A command and the Insert-mode entry after it that one key does together: `dwi` is `cw`. */
function combinedPair(list: readonly Command[]): Tip | undefined {
  for (let i = 0; i + 1 < list.length; i++) {
    const before = list[i]
    const after = list[i + 1]
    if (before === undefined || after === undefined) {
      continue
    }
    const shorter = shorterPair(before, after)
    if (shorter !== undefined) {
      return {
        saving: 1,
        text: `\`${before.count}${before.keys}\` then \`${after.entry}\` is \`${shorter}\`, one key shorter.`,
      }
    }
  }
  if (list.some((command) => command.entry === "A" && command.text?.[0] === "<CR>")) {
    return { saving: 1, text: "`A` then `<CR>` is `o`, one key shorter." }
  }
  return undefined
}

/** The tip worth the most keys, or undefined when there's nothing useful to say. */
export function tip(keys: readonly string[]): string | undefined {
  const list = commands(keys)
  const run = repeatedRun(list)
  const pair = combinedPair(list)
  const best = pair !== undefined && (run === undefined || pair.saving > run.saving) ? pair : run
  if (best !== undefined) {
    return best.text
  }
  return keys.some((key) => ARROWS.has(key)) ? ARROW_TIP : undefined
}
