import { h, stars } from "../ui/dom"

// A scripted replay of levels being solved, for the hero. Plain DOM so the
// landing page doesn't need the editor bundle.

type Frame = {
  readonly text: string
  /** UTF-16 index of the cursor in `text`. */
  readonly cursor: number
}

type Step = Frame & {
  /** Key pressed to reach this frame, in Vim notation. */
  readonly key: string
}

type Scene = {
  readonly title: string
  readonly par: number
  readonly start: Frame
  readonly steps: readonly Step[]
}

const TYPO = "The quick brown fxo jumps over the lazy dog"
const FIXED = "The quick brown jumps over the lazy dog"
const GREETING = 'greeting = "Hello, World!"'

const SCENES: readonly Scene[] = [
  {
    title: "Kill the typo",
    par: 4,
    start: { text: TYPO, cursor: 0 },
    steps: [
      { key: "f", text: TYPO, cursor: 0 },
      { key: "f", text: TYPO, cursor: 16 },
      { key: "d", text: TYPO, cursor: 16 },
      { key: "w", text: FIXED, cursor: 16 },
    ],
  },
  {
    title: "Inside job",
    par: 3,
    start: { text: GREETING, cursor: 0 },
    steps: [
      { key: "d", text: GREETING, cursor: 0 },
      { key: "i", text: GREETING, cursor: 0 },
      { key: '"', text: 'greeting = ""', cursor: 12 },
    ],
  },
]

const KEY_INTERVAL_MS = 650
const SOLVED_PAUSE_MS = 2200
const SCENE_START_PAUSE_MS = 900

type HeroElements = {
  readonly title: HTMLElement
  readonly line: HTMLElement
  readonly keys: HTMLElement
  readonly status: HTMLElement
}

function renderLine(line: HTMLElement, text: string, cursor: number): void {
  const char = text[cursor] ?? " "
  line.replaceChildren(
    text.slice(0, cursor),
    h("span", { className: "hero-cursor" }, [char]),
    text.slice(cursor + 1),
  )
}

function renderFrame(elements: HeroElements, scene: Scene, typed: number): void {
  const frame: Frame = typed === 0 ? scene.start : (scene.steps[typed - 1] ?? scene.start)
  elements.title.textContent = `${scene.title} · par ${scene.par}`
  renderLine(elements.line, frame.text, frame.cursor)
  elements.keys.replaceChildren(
    ...scene.steps.slice(0, typed).map((step) => h("kbd", {}, [step.key])),
  )
  const solved = typed === scene.steps.length
  elements.status.textContent = solved
    ? `${stars(3)}  solved in ${typed} keys`
    : `-- NORMAL --  keys ${typed}`
  elements.status.classList.toggle("is-solved", solved)
}

function wait(ms: number): Promise<void> {
  return new Promise((resolve) => window.setTimeout(resolve, ms))
}

async function loop(elements: HeroElements): Promise<never> {
  for (let index = 0; ; index = (index + 1) % SCENES.length) {
    const scene = SCENES[index]
    if (scene === undefined) {
      continue
    }
    renderFrame(elements, scene, 0)
    await wait(SCENE_START_PAUSE_MS)
    for (let typed = 1; typed <= scene.steps.length; typed++) {
      renderFrame(elements, scene, typed)
      await wait(KEY_INTERVAL_MS)
    }
    await wait(SOLVED_PAUSE_MS)
  }
}

export function mountHeroDemo(root: HTMLElement): void {
  const elements: HeroElements = {
    title: h("p", { className: "hero-demo-title" }),
    line: h("pre", { className: "hero-demo-line" }),
    keys: h("p", { className: "hero-demo-keys" }),
    status: h("p", { className: "hero-demo-status" }),
  }
  root.replaceChildren(elements.title, elements.line, elements.keys, elements.status)

  const firstScene = SCENES[0]
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
  if (reducedMotion && firstScene !== undefined) {
    renderFrame(elements, firstScene, firstScene.steps.length)
    return
  }
  void loop(elements)
}
