// "Watch par": the level's par route played on its own text, one key at a time, with
// the keys typed so far shown underneath. It runs on a copy of the level, so the
// player's finished attempt stays as it was.
import { EditorView } from "@codemirror/view"
import type { Level } from "../challenges"
import { splitNotation } from "../keys"
import { h } from "../ui/dom"
import { createEditor } from "./editor"
import { presentGoal } from "./goal-view"
import { readableKeys } from "./lesson"
import { playKey } from "./replay"

// Slow enough to follow each key, quick enough that a 20-key route takes under 10 s.
const KEY_INTERVAL_MS = 450

export type ParPlayer = {
  readonly element: HTMLElement
  /** Plays the route from the start, replacing any run in progress. */
  readonly play: () => void
}

export function parPlayer(level: Level): ParPlayer {
  const keys = splitNotation(level.solution)
  const host = h("div", { className: "editor par-editor" })
  const typed = h("code", { className: "par-typed" })
  const rest = h("code", { className: "par-rest" })
  const element = h("div", { className: "par-player", attrs: { "aria-label": "Par route" } }, [
    host,
    h("p", { className: "par-keys" }, [typed, rest]),
  ])
  let view: EditorView | undefined
  let timer: number | undefined

  function stop(): void {
    window.clearInterval(timer)
    view?.destroy()
  }

  function play(): void {
    stop()
    const goal = presentGoal(level)
    // Not editable: the route plays itself, and stray keys mustn't change it.
    view = createEditor(
      host,
      level,
      { onChange: () => undefined },
      { extensions: [goal.extension, EditorView.editable.of(false)] },
    )
    let next = 0
    typed.textContent = ""
    rest.textContent = readableKeys(level.solution)
    timer = window.setInterval(() => {
      const key = keys[next]
      if (key === undefined || !element.isConnected || view === undefined) {
        window.clearInterval(timer)
        return
      }
      playKey(view, key)
      next++
      typed.textContent = readableKeys(keys.slice(0, next).join(""))
      rest.textContent = readableKeys(keys.slice(next).join(""))
    }, KEY_INTERVAL_MS)
  }

  return { element, play }
}
