import { Compartment, EditorSelection, EditorState, type Extension } from "@codemirror/state"
import { EditorView, drawSelection, highlightActiveLine, lineNumbers } from "@codemirror/view"
import { Vim, getCM, vim } from "@replit/codemirror-vim"
import type { Level, Preset } from "../challenges"
import { registersFor, type Register, type Snapshot } from "../goals"
import { splitNotation } from "../keys"
import { byteColToIndex, indexToByteCol } from "../text"

// A CodeMirror 6 editor running the Vim emulation, plus conversions between
// CodeMirror state and the level coordinates (1-based line, byte column).

export type EditorEvents = {
  /** Fires after any document or cursor change, and on mode changes. */
  readonly onChange: () => void
}

export type EditorOptions = {
  /** Extra extensions, e.g. the goal's target highlight. */
  readonly extensions?: Extension
}

const readOnly = new Compartment()

export function createEditor(
  parent: HTMLElement,
  level: Level,
  events: EditorEvents,
  options: EditorOptions = {},
): EditorView {
  const view = new EditorView({
    parent,
    state: levelState(level, events, options),
  })
  getCM(view)?.on("vim-mode-change", events.onChange)
  prepareRegisters(level)
  return view
}

/**
 * Mirrors room/child.lua: registers the goal reads start empty (so a retry
 * never inherits a solved register), then the level's presets apply. The
 * emulation keeps registers globally, like Vim. Mark presets are not
 * emulated; levels that need them never pass the emulation gate.
 */
function prepareRegisters(level: Level): void {
  const controller = Vim.getRegisterController()
  for (const name of registersFor(level.goal)) {
    controller.getRegister(name).setText("")
  }
  const registers: NonNullable<Preset["registers"]> = level.preset?.registers ?? {}
  for (const [name, value] of Object.entries(registers)) {
    if (typeof value === "string") {
      controller.getRegister(name).setText(value, false)
    } else {
      controller.getRegister(name).setText(`${value.join("\n")}\n`, true)
    }
  }
}

function readRegister(name: string): Register {
  const register = Vim.getRegisterController().getRegister(name)
  const text = register.toString()
  const body = register.linewise && text.endsWith("\n") ? text.slice(0, -1) : text
  return { lines: body === "" ? [] : body.split("\n"), linewise: register.linewise }
}

/** Stops edits once the attempt is over; the cursor can still move. */
export function freezeEditor(view: EditorView): void {
  view.dispatch({ effects: readOnly.reconfigure(EditorState.readOnly.of(true)) })
}

function levelState(level: Level, events: EditorEvents, options: EditorOptions): EditorState {
  const doc = level.start_text.join("\n")
  return EditorState.create({
    doc,
    selection: EditorSelection.cursor(cursorToOffset(EditorState.create({ doc }), level.cursor_start)),
    extensions: [
      // vim() must come before other keymaps so it sees keys first.
      vim({ status: false }),
      lineNumbers(),
      drawSelection(),
      highlightActiveLine(),
      readOnly.of(EditorState.readOnly.of(false)),
      options.extensions ?? [],
      EditorView.updateListener.of((update) => {
        if (update.docChanged || update.selectionSet) {
          events.onChange()
        }
      }),
    ],
  })
}

/** Restarts the level in place: fresh text, cursor, undo history and Normal mode. */
export function resetEditor(
  view: EditorView,
  level: Level,
  events: EditorEvents,
  options: EditorOptions = {},
): void {
  const cm = getCM(view)
  if (cm?.state.vim?.insertMode === true || cm?.state.vim?.visualMode === true) {
    Vim.handleKey(cm, "<Esc>", "user")
  }
  view.setState(levelState(level, events, options))
  getCM(view)?.on("vim-mode-change", events.onChange)
  prepareRegisters(level)
}

function cursorToOffset(state: EditorState, cursor: readonly [number, number]): number {
  const line = state.doc.line(cursor[0])
  return line.from + byteColToIndex(line.text, cursor[1])
}

/** @param registerNames Registers to capture, usually registersFor(goal). */
export function snapshot(view: EditorView, registerNames: readonly string[] = []): Snapshot {
  const { doc, selection } = view.state
  const head = selection.main.head
  const line = doc.lineAt(head)
  return {
    lines: doc.toString().split("\n"),
    cursor: [line.number, indexToByteCol(line.text, head - line.from)],
    registers: Object.fromEntries(registerNames.map((name) => [name, readRegister(name)])),
  }
}

export const VimMode = { Normal: "NORMAL", Insert: "INSERT", Visual: "VISUAL" } as const
export type VimMode = (typeof VimMode)[keyof typeof VimMode]

export function vimMode(view: EditorView): VimMode {
  const state = getCM(view)?.state.vim
  if (state?.insertMode === true) {
    return VimMode.Insert
  }
  if (state?.visualMode === true) {
    return VimMode.Visual
  }
  return VimMode.Normal
}

export function isNormalMode(view: EditorView): boolean {
  return vimMode(view) === VimMode.Normal
}

/**
 * Feeds Vim key notation ("ciwfoo<Esc>") to the emulation, one key at a time.
 * In Insert mode a browser delivers printable characters through DOM input
 * rather than the Vim key handler, so they are inserted directly here.
 */
export function typeKeys(view: EditorView, notation: string): void {
  const cm = getCM(view)
  if (cm === null) {
    throw new Error("Vim emulation is not attached to this editor")
  }
  for (const key of splitNotation(notation)) {
    const isText = !key.startsWith("<") || key === "<"
    if (cm.state.vim?.insertMode === true && isText) {
      view.dispatch(view.state.replaceSelection(key))
    } else {
      Vim.handleKey(cm, key, "user")
    }
  }
}
