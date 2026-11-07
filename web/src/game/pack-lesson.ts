import type { Lesson, LessonExample } from "../challenges"
import { byteColToIndex } from "../text"
import { h } from "../ui/dom"
import { readableKeys } from "./lesson"

// A pack's lesson (see lua/vimdojo/lesson_panel.lua for the plugin's), shown in the
// stage before the pack's first level or from the pack's Lesson link.

/** A line split around the character the cursor is on. */
export type CursorLine = {
  readonly beforeCursor: string
  readonly cursor: string
  readonly afterCursor: string
}

/** @param byteCol The cursor's 0-based UTF-8 byte column, as lessons store it. */
export function splitAtCursor(line: string, byteCol: number): CursorLine {
  const index = byteColToIndex(line, byteCol)
  const rest = line.slice(index)
  const cursor = Array.from(rest)[0] ?? ""
  return { beforeCursor: line.slice(0, index), cursor, afterCursor: rest.slice(cursor.length) }
}

/** Plays the level the lesson leads into. */
export type LessonStart = { readonly label: string; readonly run: () => void }

// Mirrors KEYS_COLUMN_MAX in lesson_panel.lua: longer keys, such as a concept like
// "macro stops on failure", get a row of their own so the keys column stays narrow.
const KEYS_COLUMN_MAX = 8

function codeLine(line: string, byteCol: number | undefined): HTMLElement {
  if (byteCol === undefined) {
    return h("code", {}, [line])
  }
  const parts = splitAtCursor(line, byteCol)
  return h("code", {}, [
    parts.beforeCursor,
    h("span", { className: "lesson-cursor" }, [parts.cursor]),
    parts.afterCursor,
  ])
}

function exampleElement(example: LessonExample): HTMLElement {
  return h("p", { className: "lesson-example" }, [
    codeLine(example.before, example.cursor),
    h("kbd", {}, [readableKeys(example.keys)]),
    codeLine(example.after, example.cursor_after),
  ])
}

function wide(keys: string): { className?: string } {
  return Array.from(keys).length > KEYS_COLUMN_MAX ? { className: "lesson-wide" } : {}
}

export type LessonView = { readonly element: HTMLElement; readonly startButton?: HTMLButtonElement }

export function lessonView(title: string, lesson: Lesson, start?: LessonStart): LessonView {
  const commands = h(
    "dl",
    { className: "lesson-commands" },
    lesson.commands.flatMap((command) => [
      h("dt", wide(command.keys), [h("kbd", {}, [command.keys])]),
      h("dd", wide(command.keys), [
        h("p", {}, [command.text]),
        command.example && exampleElement(command.example),
      ]),
    ]),
  )
  const startButton =
    start && h("button", { className: "primary", attrs: { type: "button" } }, [start.label])
  startButton?.addEventListener("click", () => start?.run())
  const element = h(
    "section",
    { className: "lesson", attrs: { "aria-label": `${title} lesson` } },
    [
      h("h3", { className: "level-title" }, [`${title} · lesson`]),
      ...lesson.intro.map((paragraph) => h("p", {}, [paragraph])),
      commands,
      h("p", { className: "aside" }, [
        "More in Neovim: ",
        lesson.help.map((tag) => `:help ${tag}`).join(" · "),
      ]),
      startButton && h("div", { className: "results-actions" }, [startButton]),
    ],
  )
  return startButton === undefined ? { element } : { element, startButton }
}
