// Plays a key-notation string into a demo editor, one key at a time, so the results
// card can show the par route being typed. Real keyboard events can't be faked
// (browsers ignore synthetic ones), so each key goes to the Vim emulation directly,
// and text it leaves to the browser (Insert mode, the search prompt) is inserted here.
import type { EditorView } from "@codemirror/view"
import { Vim, getCM } from "@replit/codemirror-vim"
import { splitNotation } from "../keys"

const TYPED_TEXT: Readonly<Record<string, string>> = {
  "<CR>": "\n",
  "<Space>": " ",
  "<lt>": "<",
  "<Tab>": "\t",
}

/** What a key types as text, if it's text. */
function textOf(key: string): string | undefined {
  return TYPED_TEXT[key] ?? (key.startsWith("<") && key.length > 1 ? undefined : key)
}

// The prompt reacts to keyCode, which a constructed KeyboardEvent leaves at 0.
const PROMPT_KEYS: Readonly<Record<string, { key: string; keyCode: number }>> = {
  "<CR>": { key: "Enter", keyCode: 13 },
  "<Esc>": { key: "Escape", keyCode: 27 },
}

/** The emulation's prompt for `/`, `?` and `:`, while it's open. */
function promptInput(view: EditorView): HTMLInputElement | null {
  const dialog: unknown = getCM(view)?.state.dialog
  return dialog instanceof HTMLElement ? dialog.querySelector("input") : null
}

function typeInPrompt(input: HTMLInputElement, key: string): void {
  const promptKey = PROMPT_KEYS[key]
  if (promptKey !== undefined) {
    const event = new KeyboardEvent("keydown", { key: promptKey.key, bubbles: true })
    Object.defineProperty(event, "keyCode", { value: promptKey.keyCode })
    input.dispatchEvent(event)
    return
  }
  if (key === "<BS>") {
    input.value = input.value.slice(0, -1)
  } else {
    input.value += textOf(key) ?? ""
  }
  input.dispatchEvent(new Event("input", { bubbles: true }))
}

/** Sends one key, in Vim notation, as if it had been typed. */
export function playKey(view: EditorView, key: string): void {
  const input = promptInput(view)
  if (input !== null) {
    typeInPrompt(input, key)
    // Closing the prompt only signals; nothing redraws the editor until its next
    // update, so the prompt would stay on screen and the cursor where it was.
    view.dispatch({})
    return
  }
  const cm = getCM(view)
  if (cm === null || Vim.handleKey(cm, key, "user")) {
    return
  }
  // The emulation leaves Insert-mode text to the browser.
  if (key === "<BS>") {
    const { from } = view.state.selection.main
    if (from > 0) {
      view.dispatch({ changes: { from: from - 1, to: from }, selection: { anchor: from - 1 } })
    }
    return
  }
  const text = textOf(key)
  if (text === undefined || cm.state.vim?.insertMode !== true) {
    return
  }
  // Replace mode (`R`) types over the character under the cursor, except at a line's end.
  const { from } = view.state.selection.main
  const overwrite = cm.state.overwrite === true && from < view.state.doc.lineAt(from).to
  view.dispatch({
    changes: { from, to: overwrite ? from + 1 : from, insert: text },
    selection: { anchor: from + text.length },
  })
}

export function playKeys(view: EditorView, notation: string): void {
  for (const key of splitNotation(notation)) {
    playKey(view, key)
  }
}
