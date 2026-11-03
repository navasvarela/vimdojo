import { score, type Stars } from "../scoring"
import type { Level } from "../challenges"

// Port of lua/vimdojo/game.lua:
//   ready --(first key)--> playing --(goal met)--> finished

// Centisecond precision, matching the plugin, so both score the same input.
const SECONDS_PRECISION = 100
const MS_PER_SECOND = 1000

export type Outcome = {
  readonly keys: number
  readonly seconds: number
  readonly hinted: boolean
  readonly stars: Stars
  readonly points: number
}

/** Why an attempt's keys can't be replayed, so it can't be submitted. */
export type UnloggedReason = "pasted" | "unnamed_key"

/** The keys of an attempt, as game.lua's key_log returns them. */
export type KeyLog = { readonly keys: readonly string[]; readonly deltas_ms: readonly number[] }

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
  private readonly keyNames: string[] = []
  private readonly keyTimes: number[] = []
  private unlogged: UnloggedReason | undefined

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

  /**
   * Counts one typed key and keeps it for the key log. An undefined name is a key
   * that counts but can't be named, so the attempt can't be replayed.
   */
  press(name: string | undefined): void {
    if (this.state.status === "finished") {
      return
    }
    this.countKeys(1)
    if (name === undefined) {
      this.unlogged ??= "unnamed_key"
      return
    }
    this.keyNames.push(name)
    this.keyTimes.push(this.clock())
  }

  /** Pasted text counts, but a replay of the typed keys can't reproduce it. */
  paste(count: number): void {
    if (this.state.status === "finished") {
      return
    }
    this.unlogged = "pasted"
    this.countKeys(count)
  }

  /** Why the attempt can't be submitted, if it can't. */
  get unloggedReason(): UnloggedReason | undefined {
    return this.unlogged
  }

  /**
   * Port of Session:key_log in game.lua: each gap comes from rounded absolute times,
   * so the gaps add up to the time from the first key to the last.
   */
  keyLog(): KeyLog | undefined {
    if (this.unlogged !== undefined) {
      return undefined
    }
    let previous: number | undefined
    const deltas = this.keyTimes.map((seconds) => {
      const ms = Math.floor(seconds * MS_PER_SECOND + 0.5)
      const delta = previous === undefined ? 0 : ms - previous
      previous = ms
      return delta
    })
    return { keys: [...this.keyNames], deltas_ms: deltas }
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
