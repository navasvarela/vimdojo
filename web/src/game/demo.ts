import type { EditorView } from "@codemirror/view"
import { nextLevel, type Level, type Pack } from "../challenges"
import { isMet, registersFor } from "../goals"
import { dailyDate, dailyPool, dayNumber, pickDaily } from "../daily"
import { BoardsApi } from "../boards/api"
import { type Challenge, challengeResult } from "../challenge-link"
import { keyNotation } from "../key-notation"
import { isCountableKeydown, pastedKeyCount } from "../keys"
import { levelHash } from "../level-hash"
import {
  currentStreak,
  hasSolvedAny,
  isCompleted,
  recordDaily,
  recordResult,
  unlockedAll,
  type Progress,
} from "../progress"
import {
  EXPORT_FILE_NAME,
  loadProgress,
  parseJsonProgress,
  saveProgress,
  serializeProgress,
} from "../storage"
import { shareText } from "../share"
import { h, stars } from "../ui/dom"
import { createEditor, freezeEditor, isNormalMode, resetEditor, snapshot, vimMode } from "./editor"
import { presentGoal, type GoalPresentation } from "./goal-view"
import { readableKeys, SOLUTION_HIDDEN } from "./lesson"
import { RunError, RunsApi, type Run, VERIFY_POLL_MS, VERIFY_POLL_TRIES, verdictText } from "./runs"
import { Session, type Outcome, type UnloggedReason } from "./session"
import { lessonView } from "./pack-lesson"
import { parPlayer } from "./par-player"
import { tip } from "./tips"

const UNLOGGED_TEXT: Readonly<Record<UnloggedReason, string>> = {
  pasted: "This attempt included pasted text, so it can't go on the leaderboards.",
  unnamed_key: "This attempt used a key the demo can't record, so it can't go on the leaderboards.",
}
const STILL_VERIFYING = "Still verifying. Your place will show on the leaderboards once it's done."

function wait(ms: number): Promise<void> {
  return new Promise((resolve) => window.setTimeout(resolve, ms))
}

// 100 ms keeps the timer readable to a tenth of a second.
const STATUS_REFRESH_MS = 100

// Game controls use Alt so they never collide with Vim keys, and are never
// counted. KeyboardEvent.code is used because Alt+letter types a different
// character on macOS.
const Control = { Hint: "KeyH", Reset: "KeyR", Next: "KeyN" } as const

type Play = {
  readonly level: Level
  /** Set when this is the daily challenge. */
  readonly dailyDate: string | undefined
  readonly view: EditorView
  readonly goal: GoalPresentation
  readonly hint: HTMLElement
  readonly status: HTMLElement
  session: Session
  ticker: number | undefined
}

type Daily = { readonly date: string; readonly level: Level }

type DemoElements = {
  readonly daily: HTMLElement
  readonly list: HTMLOListElement
  readonly stage: HTMLElement
  readonly message: HTMLParagraphElement
}

const clock = (): number => performance.now() / 1000

/** A "beat my keys" link, with the level's title when any pack has it. */
export type ChallengeOffer = { readonly challenge: Challenge; readonly title: string | undefined }

export class Demo {
  private progress: Progress
  private readonly runs = new RunsApi()
  private readonly boards = new BoardsApi()
  private play: Play | undefined
  private challenge: Challenge | undefined
  private readonly elements: DemoElements

  constructor(
    private readonly root: HTMLElement,
    private readonly packs: readonly Pack[],
    private readonly storage: Storage | undefined,
    offer?: ChallengeOffer,
  ) {
    const loaded = loadProgress(storage)
    this.progress = loaded.progress
    this.elements = this.render()
    if (loaded.status === "unavailable") {
      this.say("Progress can't be saved in this browser (storage is disabled).")
    } else if (loaded.status === "corrupt") {
      this.say("Saved progress was unreadable, so the demo started fresh.")
    }
    if (offer !== undefined) {
      this.acceptChallenge(offer)
    }
  }

  /** Challenges ignore locks, like the daily: the link is for one level. */
  private acceptChallenge({ challenge, title }: ChallengeOffer): void {
    const inDemo = this.packs.some((pack) => pack.levels.some((l) => l.id === challenge.levelId))
    if (inDemo) {
      this.challenge = challenge
      this.start(challenge.levelId)
    } else {
      // In the stage, where a level would be: that's where the visitor is looking.
      const text =
        title === undefined
          ? "That challenge link names a level this site doesn't have."
          : `"${title}" is a level in the Neovim plugin, not the demo. Install the plugin below, then beat ${challenge.keys} keys there.`
      this.elements.stage.replaceChildren(h("p", { className: "challenge" }, [text]))
    }
  }

  private render(): DemoElements {
    const daily = h("div", { className: "daily" })
    const list = h("ol", { className: "level-list", attrs: { "aria-label": "Demo levels" } })
    const stage = h("section", { className: "stage", attrs: { "aria-live": "polite" } }, [
      h("p", { className: "stage-empty" }, [
        "Pick a level to start. The timer waits for your first key.",
      ]),
    ])
    const message = h("p", { className: "demo-message", attrs: { role: "status" } })
    const exportButton = h("button", { className: "link-button", attrs: { type: "button" } }, [
      "Export progress",
    ])
    const importInput = h("input", {
      className: "visually-hidden",
      attrs: { type: "file", accept: "application/json,.json", id: "import-progress" },
    })
    const importLabel = h(
      "label",
      { className: "link-button", attrs: { for: "import-progress" } },
      ["Import progress"],
    )
    exportButton.addEventListener("click", () => this.exportProgress())
    importInput.addEventListener("change", () => void this.importProgress(importInput))

    this.root.replaceChildren(
      h("p", { className: "emulation-banner" }, [
        "The demo uses a Vim emulation. For the real thing, ",
        h("a", { attrs: { href: "#install" } }, ["install the Neovim plugin"]),
        ".",
      ]),
      h("div", { className: "demo-grid" }, [
        h("nav", { className: "sidebar" }, [
          daily,
          list,
          h("div", { className: "progress-actions" }, [exportButton, importLabel, importInput]),
        ]),
        stage,
      ]),
      message,
    )
    const elements = { daily, list, stage, message }
    this.renderDaily(elements.daily)
    this.renderList(elements.list)
    return elements
  }

  /** Today's (UTC) daily challenge: the same level the plugin picks. */
  private todaysDaily(): Daily | undefined {
    const day = dayNumber(Date.now())
    const levelId = pickDaily(dailyPool(this.packs), day)
    const level = this.packs.flatMap((pack) => pack.levels).find((l) => l.id === levelId)
    return level === undefined ? undefined : { date: dailyDate(day), level }
  }

  /** "3-day streak (best 5)", or undefined with no streak alive. */
  private streakText(): string | undefined {
    const current = currentStreak(this.progress, dayNumber(Date.now()))
    const best = this.progress.daily?.best
    return current === 0 || best === undefined ? undefined : `${current}-day streak (best ${best})`
  }

  private renderDaily(container: HTMLElement): void {
    const today = this.todaysDaily()
    if (today === undefined) {
      container.replaceChildren()
      return
    }
    const record = this.progress.levels[today.level.id]
    const button = h(
      "button",
      {
        className: "level-button",
        attrs: {
          type: "button",
          ...(this.play?.dailyDate === today.date ? { "aria-current": "true" } : {}),
        },
      },
      [
        h("span", { className: "stars", attrs: { "aria-hidden": "true" } }, [
          stars(record?.stars ?? 0),
        ]),
        h("span", {}, [today.level.title]),
      ],
    )
    button.addEventListener("click", () => this.startDaily())
    const streak = this.streakText()
    container.replaceChildren(
      h("p", { className: "pack-title" }, [
        `Daily · ${today.date}${streak === undefined ? "" : ` · ${streak}`}`,
      ]),
      button,
    )
  }

  private renderList(list: HTMLOListElement): void {
    const unlocked = unlockedAll(this.packs)
    list.replaceChildren(
      ...this.packs.map((pack) =>
        h("li", {}, [
          h("p", { className: "pack-title" }, [pack.title, this.lessonLink(pack)]),
          h(
            "ol",
            {},
            pack.levels.map((level) => {
              const record = this.progress.levels[level.id]
              const button = h(
                "button",
                {
                  className: "level-button",
                  attrs: {
                    type: "button",
                    "data-level": level.id,
                    ...(this.play?.level.id === level.id ? { "aria-current": "true" } : {}),
                  },
                },
                [
                  h("span", { className: "stars", attrs: { "aria-hidden": "true" } }, [
                    stars(record?.stars ?? 0),
                  ]),
                  h("span", {}, [level.title]),
                  h("span", { className: "visually-hidden" }, [
                    record ? `, best ${record.stars} of 3 stars` : ", not solved yet",
                  ]),
                ],
              )
              button.disabled = !unlocked.has(level.id)
              button.addEventListener("click", () => this.choose(pack, level))
              return h("li", {}, [button])
            }),
          ),
        ]),
      ),
    )
  }

  private lessonLink(pack: Pack): HTMLButtonElement | undefined {
    if (pack.lesson === undefined) {
      return undefined
    }
    const link = h("button", { className: "link-button lesson-link", attrs: { type: "button" } }, [
      "Lesson",
    ])
    link.addEventListener("click", () => {
      const next = pack.levels.find((level) => !isCompleted(this.progress, level.id))
      this.showLesson(pack, next)
    })
    return link
  }

  /** A pack's lesson helps most before its first level, so it comes first until one is solved. */
  private choose(pack: Pack, level: Level): void {
    if (pack.lesson === undefined || hasSolvedAny(this.progress, pack)) {
      this.start(level.id)
    } else {
      this.showLesson(pack, level)
    }
  }

  private showLesson(pack: Pack, level: Level | undefined): void {
    if (pack.lesson === undefined) {
      return
    }
    this.stop()
    const start =
      level === undefined
        ? undefined
        : { label: `Start "${level.title}"`, run: () => this.start(level.id) }
    const view = lessonView(pack.title, pack.lesson, start)
    this.elements.stage.replaceChildren(view.element)
    // Enter starts the level, but the lesson is read from the top, so focusing mustn't scroll.
    view.startButton?.focus({ preventScroll: true })
  }

  start(levelId: string): void {
    const level = this.packs.flatMap((pack) => pack.levels).find((l) => l.id === levelId)
    if (level !== undefined) {
      this.open(level, undefined)
    }
  }

  /** The daily ignores locks: everyone plays the same level that day. */
  startDaily(): void {
    const today = this.todaysDaily()
    if (today !== undefined) {
      this.open(today.level, today.date)
    }
  }

  private retry(play: Play): void {
    this.open(play.level, play.dailyDate)
  }

  private open(level: Level, dailyDate: string | undefined): void {
    this.stop()
    const goal = presentGoal(level)
    const editorHost = h("div", { className: "editor" })
    const status = h("p", { className: "statusline", attrs: { "aria-live": "off" } })
    const hint = h("p", { className: "hint" }, [
      h("kbd", {}, ["Alt"]),
      "+",
      h("kbd", {}, ["H"]),
      " shows a hint (caps the attempt at 2 stars)",
    ])
    const challenge = this.challenge?.levelId === level.id ? this.challenge : undefined
    this.elements.stage.replaceChildren(
      h("h3", { className: "level-title" }, [level.title]),
      ...(challenge === undefined
        ? []
        : [
            h("p", { className: "challenge" }, [
              `Challenge: someone solved this in ${challenge.keys} keys. Can you beat it?`,
            ]),
          ]),
      h("p", { className: "level-description" }, [level.description]),
      goal.element,
      h("p", { className: "par" }, [`Par: ${level.par_keys} keys · ${level.par_seconds}s`]),
      editorHost,
      status,
      hint,
      h("p", { className: "controls" }, [
        h("kbd", {}, ["Alt"]),
        "+",
        h("kbd", {}, ["R"]),
        " reset · ",
        h("kbd", {}, ["Alt"]),
        "+",
        h("kbd", {}, ["N"]),
        " next level",
      ]),
    )
    const view = createEditor(
      editorHost,
      level,
      { onChange: () => this.scheduleCheck() },
      {
        extensions: goal.extension,
      },
    )
    const play: Play = {
      level,
      dailyDate,
      view,
      goal,
      hint,
      status,
      session: new Session(level, clock),
      ticker: undefined,
    }
    this.play = play
    view.dom.addEventListener("keydown", (event) => this.onKeydown(play, event), { capture: true })
    // Pasted or dropped text costs what typing it would, so it can't beat par.
    view.dom.addEventListener("paste", (event) => this.onInsertedText(play, event.clipboardData), {
      capture: true,
    })
    view.dom.addEventListener("drop", (event) => this.onInsertedText(play, event.dataTransfer), {
      capture: true,
    })
    play.ticker = window.setInterval(() => this.renderStatus(play), STATUS_REFRESH_MS)
    this.renderStatus(play)
    this.renderDaily(this.elements.daily)
    this.renderList(this.elements.list)
    view.focus()
  }

  private stop(): void {
    const play = this.play
    if (play === undefined) {
      return
    }
    window.clearInterval(play.ticker)
    play.view.destroy()
    this.play = undefined
  }

  private onKeydown(play: Play, event: KeyboardEvent): void {
    if (event.altKey && !event.ctrlKey && !event.metaKey) {
      this.onControl(play, event)
      return
    }
    // Cmd shortcuts (reload, copy) belong to the browser, not to Vim.
    if (event.metaKey || !isCountableKeydown(event)) {
      return
    }
    play.session.press(keyNotation(event))
  }

  private onInsertedText(play: Play, data: DataTransfer | null): void {
    const text = data?.getData("text/plain") ?? ""
    if (text !== "") {
      play.session.paste(pastedKeyCount(text))
    }
  }

  private onControl(play: Play, event: KeyboardEvent): void {
    const actions: Record<string, () => void> = {
      [Control.Hint]: () => this.showHint(play),
      [Control.Reset]: () => this.reset(play),
      [Control.Next]: () => this.startNext(play.level.id),
    }
    const action = actions[event.code]
    if (action !== undefined) {
      event.preventDefault()
      event.stopPropagation()
      action()
    }
  }

  private showHint(play: Play): void {
    if (play.session.status === "finished") {
      return
    }
    play.session.useHint()
    play.hint.replaceChildren(h("strong", {}, ["Hint: "]), play.level.hint)
  }

  private reset(play: Play): void {
    if (play.session.status === "finished") {
      return
    }
    const hinted = play.session.hinted
    play.session = new Session(play.level, clock)
    if (hinted) {
      play.session.useHint()
    }
    resetEditor(
      play.view,
      play.level,
      { onChange: () => this.scheduleCheck() },
      {
        extensions: play.goal.extension,
      },
    )
    play.view.focus()
  }

  private startNext(levelId: string): void {
    const next = nextLevel(this.packs, levelId)
    if (next !== undefined) {
      this.start(next.id)
    }
  }

  // Selection and mode-change events fire while the emulation is still
  // handling the key; checking on a microtask sees the settled state.
  private scheduleCheck(): void {
    queueMicrotask(() => {
      const play = this.play
      if (play !== undefined) {
        this.checkGoal(play)
      }
    })
  }

  private checkGoal(play: Play): void {
    if (play.session.status !== "playing" || !isNormalMode(play.view)) {
      return
    }
    const state = snapshot(play.view, registersFor(play.level.goal))
    if (isMet(play.level.goal, state, play.level.start_text)) {
      this.complete(play)
    }
  }

  private complete(play: Play): void {
    const outcome = play.session.finish()
    window.clearInterval(play.ticker)
    this.renderStatus(play)
    freezeEditor(play.view)
    this.progress = recordResult(this.progress, play.level.id, outcome)
    // By level, not by how it was opened: the same level is in the list too.
    if (this.todaysDaily()?.level.id === play.level.id) {
      this.progress = recordDaily(this.progress, dayNumber(Date.now()))
    }
    if (!saveProgress(this.storage, this.progress)) {
      this.say("Solved! (Progress could not be saved in this browser.)")
    }
    this.renderDaily(this.elements.daily)
    this.renderList(this.elements.list)
    this.showResults(play, outcome)
  }

  private showResults(play: Play, outcome: Outcome): void {
    const record = this.progress.levels[play.level.id]
    const next = nextLevel(this.packs, play.level.id)
    // By level, not by how it was opened: the same level is in the list too.
    const solutionHidden = this.todaysDaily()?.level.id === play.level.id
    const nextButton = next
      ? h("button", { className: "primary", attrs: { type: "button" } }, ["Next level (N)"])
      : undefined
    const retryButton = h("button", { attrs: { type: "button" } }, ["Retry (R)"])
    const copyButton = h("button", { attrs: { type: "button" } }, ["Copy result (C)"])
    const challenge = this.challenge?.levelId === play.level.id ? this.challenge : undefined
    // Not on today's daily: the route would give the day's board away.
    const parRoute = solutionHidden ? undefined : parPlayer(play.level)
    const watchButton = parRoute && h("button", { attrs: { type: "button" } }, ["Watch par (W)"])
    const explain = play.level.explain
    const share = shareText({
      levelId: play.level.id,
      levelTitle: play.level.title,
      parKeys: play.level.par_keys,
      dailyDate: play.dailyDate,
      outcome,
    })
    // Only an attempt over par gets a tip: at or under par, there's nothing to shorten.
    const log = play.session.keyLog()
    const advice =
      log !== undefined && outcome.keys > play.level.par_keys ? tip(log.keys) : undefined
    const online = h("div", { className: "results-online" })
    void this.offerSubmit(play, outcome, online)
    const card = h(
      "section",
      {
        className: "results",
        attrs: { role: "dialog", "aria-label": `${play.level.title} solved`, tabindex: "-1" },
      },
      [
        h(
          "p",
          { className: "results-stars", attrs: { "aria-label": `${outcome.stars} of 3 stars` } },
          [stars(outcome.stars)],
        ),
        h("p", { className: "results-points" }, [`${outcome.points} points`]),
        h("dl", { className: "results-stats" }, [
          h("dt", {}, ["Keys"]),
          h("dd", {}, [`${outcome.keys} (par ${play.level.par_keys})`]),
          h("dt", {}, ["Time"]),
          h("dd", {}, [`${outcome.seconds.toFixed(1)}s (par ${play.level.par_seconds}s)`]),
          record && h("dt", {}, ["Best"]),
          record &&
            h("dd", {}, [
              `${record.best_keys} keys · ${record.best_seconds.toFixed(1)}s · ${stars(record.stars)}`,
            ]),
          solutionHidden && h("dt", {}, ["Streak"]),
          solutionHidden && h("dd", {}, [this.streakText()]),
          h("dt", {}, ["Par"]),
          h("dd", {}, [
            solutionHidden ? SOLUTION_HIDDEN : h("code", {}, [readableKeys(play.level.solution)]),
          ]),
          !solutionHidden && h("dt", {}, ["Learn"]),
          !solutionHidden && h("dd", {}, [play.level.teaches.join(", ")]),
          !solutionHidden && explain !== undefined && h("dt", {}, ["Steps"]),
          !solutionHidden &&
            explain !== undefined &&
            h("dd", {}, [
              h(
                "ol",
                { className: "steps" },
                explain.map((step) =>
                  h("li", {}, [h("code", {}, [readableKeys(step.keys)]), ` ${step.text}`]),
                ),
              ),
            ]),
          challenge !== undefined && h("dt", {}, ["Challenge"]),
          challenge !== undefined && h("dd", {}, [challengeResult(challenge, outcome.keys)]),
          advice !== undefined && h("dt", {}, ["Tip"]),
          advice !== undefined && h("dd", {}, [advice]),
        ]),
        outcome.hinted && h("p", { className: "results-note" }, ["Hint used: capped at 2 stars."]),
        h("div", { className: "results-actions" }, [
          nextButton,
          retryButton,
          copyButton,
          watchButton,
        ]),
        online,
      ],
    )
    nextButton?.addEventListener("click", () => this.startNext(play.level.id))
    retryButton.addEventListener("click", () => this.retry(play))
    copyButton.addEventListener("click", () => void this.copyResult(share))
    const watchPar = (): void => {
      if (parRoute !== undefined) {
        card.append(parRoute.element)
        parRoute.play()
      }
    }
    watchButton?.addEventListener("click", watchPar)
    card.addEventListener("keydown", (event) => {
      if (event.key === "r" || event.key === "R") {
        event.preventDefault()
        this.retry(play)
      } else if ((event.key === "w" || event.key === "W") && parRoute !== undefined) {
        event.preventDefault()
        watchPar()
      } else if (event.key === "s" || event.key === "S") {
        const submit = online.querySelector("button")
        if (submit !== null && !submit.disabled) {
          event.preventDefault()
          submit.click()
        }
      } else if (event.key === "c" || event.key === "C") {
        event.preventDefault()
        void this.copyResult(share)
      } else if ((event.key === "n" || event.key === "N") && next) {
        event.preventDefault()
        this.startNext(play.level.id)
      }
    })
    this.elements.stage.append(card)
    ;(nextButton ?? retryButton).focus()
  }

  /** The leaderboard part of the results card. It asks the server only after a solve. */
  private async offerSubmit(play: Play, outcome: Outcome, container: HTMLElement): Promise<void> {
    const reason = play.session.unloggedReason
    if (reason !== undefined) {
      container.replaceChildren(h("p", { className: "results-note" }, [UNLOGGED_TEXT[reason]]))
      return
    }
    const signedIn = await this.runs.signedIn()
    if (!container.isConnected || signedIn === undefined) {
      return
    }
    if (!signedIn) {
      container.replaceChildren(
        h("p", { className: "results-note" }, [
          h("a", { attrs: { href: `${import.meta.env.BASE_URL}account/` } }, ["Sign in"]),
          " to put your runs on the leaderboards.",
        ]),
      )
      return
    }
    const button = h("button", { attrs: { type: "button" } }, ["Submit to the leaderboards (S)"])
    const note = h("p", { className: "results-note", attrs: { "aria-live": "polite" } })
    button.addEventListener("click", () => void this.submit(play, outcome, button, note))
    container.replaceChildren(button, note)
  }

  private async submit(
    play: Play,
    outcome: Outcome,
    button: HTMLButtonElement,
    note: HTMLElement,
  ): Promise<void> {
    const log = play.session.keyLog()
    if (log === undefined) {
      return
    }
    button.disabled = true
    note.textContent = "Sending your keys to be replayed in Neovim…"
    try {
      const submitted = await this.runs.submit({
        level_id: play.level.id,
        level_hash: await levelHash(play.level),
        log,
        claimed: { keys: outcome.keys, seconds: outcome.seconds, hinted: outcome.hinted },
      })
      const verdict = await this.awaitVerdict(submitted.id, note)
      if (verdict !== undefined) {
        note.textContent = await this.verdictWithPlace(play.level.id, verdict)
      }
    } catch (error) {
      note.textContent = error instanceof RunError ? error.message : "Something went wrong."
      button.disabled = false
    }
  }

  /** @returns undefined if the card was closed, or the replay took too long. */
  private async awaitVerdict(runId: string, note: HTMLElement): Promise<Run | undefined> {
    for (let tries = 0; tries < VERIFY_POLL_TRIES; tries++) {
      const run = await this.runs.run(runId)
      if (run.status !== "pending") {
        return run
      }
      note.textContent = "Verifying in Neovim…"
      await wait(VERIFY_POLL_MS)
      if (!note.isConnected) {
        return undefined
      }
    }
    note.textContent = STILL_VERIFYING
    return undefined
  }

  /** On today's daily the place that matters is today's, as in the plugin. */
  private async verdictWithPlace(levelId: string, run: Run): Promise<string> {
    const text = verdictText(run) ?? STILL_VERIFYING
    if (run.status !== "verified" && run.status !== "mismatch") {
      return text
    }
    const isDaily = this.todaysDaily()?.level.id === levelId
    const mine = await (isDaily ? this.boards.ownDailyRank() : this.boards.ownRank(levelId)).catch(
      () => undefined,
    )
    if (mine?.rank == null) {
      return text
    }
    return `${text} You're #${mine.rank}${isDaily ? " today" : ""}.`
  }

  private async copyResult(text: string): Promise<void> {
    try {
      await navigator.clipboard.writeText(text)
      this.say("Result copied. Paste it anywhere: it doesn't give the solution away.")
    } catch {
      // The Clipboard API needs a secure context and permission; show the text
      // so it can still be copied by hand.
      this.say(text)
    }
  }

  private renderStatus(play: Play): void {
    const { session } = play
    const parts = [
      `-- ${vimMode(play.view)} --`,
      `time ${session.elapsed().toFixed(1)}s`,
      `keys ${session.keys}`,
      ...(session.hinted ? ["hinted"] : []),
    ]
    play.status.textContent = parts.join("  ·  ")
  }

  private exportProgress(): void {
    const blob = new Blob([serializeProgress(this.progress)], { type: "application/json" })
    const url = URL.createObjectURL(blob)
    const link = h("a", { attrs: { href: url, download: EXPORT_FILE_NAME } })
    link.click()
    URL.revokeObjectURL(url)
    this.say(`Downloaded ${EXPORT_FILE_NAME}.`)
  }

  private async importProgress(input: HTMLInputElement): Promise<void> {
    const file = input.files?.[0]
    input.value = ""
    if (file === undefined) {
      return
    }
    const imported = parseJsonProgress(await file.text())
    if (imported === undefined) {
      this.say(`${file.name} is not a vimdojo progress file.`)
      return
    }
    this.progress = imported
    saveProgress(this.storage, this.progress)
    this.renderList(this.elements.list)
    this.say(`Imported progress from ${file.name}.`)
  }

  private say(text: string): void {
    this.elements.message.textContent = text
  }
}
