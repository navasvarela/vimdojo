import { score, type Stars } from "../scoring"
import type { Level } from "../challenges"

// Port of lua/vimdojo/game.lua:
//   ready --(first key)--> playing --(goal met)--> finished

// Centisecond precision, matching the plugin, so both score the same input.
const SECONDS_PRECISION = 100

export type Outcome = {
  readonly keys: number
  readonly seconds: number
  readonly hinted: boolean
  readonly stars: Stars
  readonly points: number
}

export type SessionState =
  | { readonly status: "ready" }
  | { readonly status: "playing"; readonly startedAt: number }
  | { readonly status: "finished"; readonly outcome: Outcome }

/** Monotonic time in seconds. */
export type Clock = () => number

export class Session {
  private state: SessionState = { status: "ready" }
  private keyCount = 0
  private hintUsed = false

  constructor(
    readonly level: Level,
    private readonly clock: Clock,
  ) {}

  get status(): SessionState["status"] {
    return this.state.status
  }

  get keys(): number {
    return this.keyCount
  }

  get hinted(): boolean {
    return this.hintUsed
  }

  /** The timer starts on the first key, not when the level opens. */
  countKeys(count: number): void {
    if (this.state.status === "finished") {
      return
    }
    if (this.state.status === "ready") {
      this.state = { status: "playing", startedAt: this.clock() }
    }
    this.keyCount += count
  }

  useHint(): void {
    this.hintUsed = true
  }

  elapsed(): number {
    switch (this.state.status) {
      case "ready":
        return 0
      case "playing":
        return this.clock() - this.state.startedAt
      case "finished":
        return this.state.outcome.seconds
    }
  }

  finish(): Outcome {
    if (this.state.status === "finished") {
      return this.state.outcome
    }
    const seconds = Math.floor(this.elapsed() * SECONDS_PRECISION + 0.5) / SECONDS_PRECISION
    const result = score({
      keys: this.keyCount,
      seconds,
      par_keys: this.level.par_keys,
      par_seconds: this.level.par_seconds,
      hinted: this.hintUsed,
    })
    const outcome: Outcome = { keys: this.keyCount, seconds, hinted: this.hintUsed, ...result }
    this.state = { status: "finished", outcome }
    return outcome
  }
}
