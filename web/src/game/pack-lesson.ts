import type { Lesson, LessonExample } from "../challenges"
import { byteColToIndex } from "../text"
import { h } from "../ui/dom"

// A pack's lesson (see lua/vimdojo/lesson_panel.lua for the plugin's), shown in the
// stage before the pack's first level or from the pack's Lesson link.

/** An example's line split around the character the cursor is on. */
export type ExampleLine = {
  readonly beforeCursor: string
  readonly cursor: string
  readonly afterCursor: string
}

export function exampleLine(example: LessonExample): ExampleLine {
  const index = byteColToIndex(example.before, example.cursor)
  const rest = example.before.slice(index)
  const cursor = Array.from(rest)[0] ?? ""
  return {
    beforeCursor: example.before.slice(0, index),
    cursor,
    afterCursor: rest.slice(cursor.length),
  }
}

/** Plays the level the lesson leads into. */
export type LessonStart = { readonly label: string; readonly run: () => void }

function exampleElement(example: LessonExample): HTMLElement {
  const line = exampleLine(example)
  return h("p", { className: "lesson-example" }, [
    h("code", {}, [
      line.beforeCursor,
      h("span", { className: "lesson-cursor" }, [line.cursor]),
      line.afterCursor,
    ]),
    h("kbd", {}, [example.keys]),
    h("code", {}, [example.after]),
  ])
}

export type LessonView = { readonly element: HTMLElement; readonly startButton?: HTMLButtonElement }

export function lessonView(title: string, lesson: Lesson, start?: LessonStart): LessonView {
  const commands = h(
    "dl",
    { className: "lesson-commands" },
    lesson.commands.flatMap((command) => [
      h("dt", {}, [h("kbd", {}, [command.keys])]),
      h("dd", {}, [h("p", {}, [command.text]), command.example && exampleElement(command.example)]),
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
