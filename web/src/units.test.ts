import { describe, expect, it } from "vitest"
import { TRACKS, demoPacks, loadPacks, nextLevel, parsePacks } from "./challenges"
import { dailyPool, dayNumber, pickDaily } from "./daily"
import { isCountableKeydown, pastedKeyCount, splitNotation } from "./keys"
import { emptyProgress, recordResult, unlockedByProgress } from "./progress"
import { loadProgress, saveProgress, serializeProgress, parseJsonProgress } from "./storage"
import { byteColToIndex, indexToByteCol } from "./text"
import { Session } from "./game/session"

describe("challenges", () => {
  it("parses every shipped pack in curriculum order", () => {
    const packs = loadPacks()
    expect(packs.map((p) => p.order)).toEqual([...packs.map((p) => p.order)].sort((a, b) => a - b))
    expect(packs.length).toBeGreaterThan(0)
  })

  it("keeps only web_demo levels in the demo", () => {
    for (const pack of demoPacks(loadPacks())) {
      expect(pack.levels.every((level) => level.web_demo === true)).toBe(true)
    }
  })

  it("finds the next level across packs", () => {
    const packs = loadPacks()
    const lastOfFirst = packs[0]?.levels.at(-1)
    const firstOfSecond = packs[1]?.levels[0]
    expect(lastOfFirst && nextLevel(packs, lastOfFirst.id)?.id).toBe(firstOfSecond?.id)
  })
})

describe("keys", () => {
  it.each([
    ["ffdw", ["f", "f", "d", "w"]],
    ["ciwfoo<Esc>", ["c", "i", "w", "f", "o", "o", "<Esc>"]],
    ["<C-r>a", ["<C-r>", "a"]],
    ["<C-^>", ["<C-^>"]],
    ["f<", ["f", "<"]],
    ["fé", ["f", "é"]],
  ])("splits %s like the Lua port", (notation, expected) => {
    expect(splitNotation(notation)).toEqual(expected)
  })

  it.each([
    ["j", true],
    ["$", true],
    ["Escape", true],
    ["Shift", false],
    ["Control", false],
    ["Meta", false],
    ["", false],
  ])("keydown %s countable: %s", (key, expected) => {
    expect(isCountableKeydown({ key })).toBe(expected)
  })

  it.each([
    ["hello", 5],
    ["ab\ncd", 5],
    ["ab\r\ncd", 5],
    ["é", 1],
    ["", 0],
  ])("pasting %j costs %i keys, like the Lua port", (text, expected) => {
    expect(pastedKeyCount(text)).toBe(expected)
  })
})

describe("text columns", () => {
  it.each([
    ["hello", 3, 3],
    ["héllo", 3, 2],
    ["│ x", 4, 2],
  ])("byte col in %s", (line, byteCol, index) => {
    expect(byteColToIndex(line, byteCol)).toBe(index)
    expect(indexToByteCol(line, index)).toBe(byteCol)
  })
})

function lvl(id: string) {
  return {
    id,
    title: id,
    description: id,
    start_text: ["a"],
    cursor_start: [1, 0],
    goal: { type: "cursor_at", line: 1, col: 0 },
    par_keys: 1,
    par_seconds: 1,
    hint: "h",
    solution: "l",
    teaches: ["l"],
  }
}

describe("progress", () => {
  const packs = loadPacks()

  it("unlocks only the first level of each track on fresh progress", () => {
    const firstOfEachTrack = TRACKS.map(
      (track) => packs.find((pack) => pack.track === track)?.levels[0]?.id,
    ).filter((id): id is string => id !== undefined)
    const byId = (a: string, b: string): number => a.localeCompare(b)
    expect([...unlockedByProgress(emptyProgress(), packs)].sort(byId)).toEqual(
      firstOfEachTrack.sort(byId),
    )
  })

  it("progresses each track independently, skipping unsupported levels", () => {
    const fixture = parsePacks([
      { pack: "m", title: "M", order: 1, levels: [lvl("m-1"), lvl("m-2")] },
      { pack: "s", title: "S", order: 2, track: "setup", levels: [lvl("s-1")] },
    ])
    expect([...unlockedByProgress(emptyProgress(), fixture)].sort()).toEqual(["m-1", "s-1"])
    const skipFirst = (level: { id: string }) => level.id !== "m-1"
    expect([...unlockedByProgress(emptyProgress(), fixture, skipFirst)].sort()).toEqual([
      "m-1",
      "m-2",
      "s-1",
    ])
  })

  it("merges results into independent bests", () => {
    let progress = recordResult(emptyProgress(), "a", { keys: 6, seconds: 4.5, stars: 2 })
    progress = recordResult(progress, "a", { keys: 5, seconds: 9, stars: 1 })
    expect(progress.levels["a"]).toEqual({ best_keys: 5, best_seconds: 4.5, stars: 2, attempts: 2 })
  })
})

class MemoryStorage implements Storage {
  private items = new Map<string, string>()
  get length(): number {
    return this.items.size
  }
  clear(): void {
    this.items.clear()
  }
  getItem(key: string): string | null {
    return this.items.get(key) ?? null
  }
  key(index: number): string | null {
    return [...this.items.keys()][index] ?? null
  }
  removeItem(key: string): void {
    this.items.delete(key)
  }
  setItem(key: string, value: string): void {
    this.items.set(key, value)
  }
}

class ThrowingStorage extends MemoryStorage {
  override getItem(): string | null {
    throw new Error("SecurityError")
  }
  override setItem(): void {
    throw new Error("QuotaExceededError")
  }
}

describe("storage", () => {
  it("round-trips progress", () => {
    const storage = new MemoryStorage()
    const progress = recordResult(emptyProgress(), "a", { keys: 5, seconds: 7.4, stars: 3 })
    expect(saveProgress(storage, progress)).toBe(true)
    expect(loadProgress(storage)).toEqual({ status: "loaded", progress })
  })

  it.each([
    ["missing", new MemoryStorage(), "empty"],
    ["throwing", new ThrowingStorage(), "unavailable"],
    ["absent", undefined, "unavailable"],
  ] as const)("starts fresh when storage is %s", (_name, storage, status) => {
    expect(loadProgress(storage)).toEqual({ status, progress: emptyProgress() })
  })

  it("reports corrupt data and starts fresh", () => {
    const storage = new MemoryStorage()
    storage.setItem("vimdojo.progress", '{"version":99,"levels":{}}')
    expect(loadProgress(storage).status).toBe("corrupt")
  })

  it("does not throw when saving fails", () => {
    expect(saveProgress(new ThrowingStorage(), emptyProgress())).toBe(false)
  })

  it("accepts a plugin progress.json export", () => {
    const pluginFile =
      '{"version":1,"levels":{"basic-motions-01":{"best_keys":5,"best_seconds":13.16,"attempts":1,"stars":2}}}'
    const progress = parseJsonProgress(pluginFile)
    expect(progress?.levels["basic-motions-01"]?.best_keys).toBe(5)
    expect(progress && parseJsonProgress(serializeProgress(progress))).toEqual(progress)
  })
})

describe("session", () => {
  function fakeClock() {
    let now = 100
    return { clock: () => now, advance: (s: number) => (now += s) }
  }
  const level = loadPacks()[0]?.levels[0]
  if (level === undefined) {
    throw new Error("no levels")
  }

  it("starts the timer on the first key and rounds to centiseconds", () => {
    const { clock, advance } = fakeClock()
    const session = new Session(level, clock)
    advance(30)
    expect(session.elapsed()).toBe(0)
    session.countKeys(level.par_keys)
    advance(1.234)
    expect(session.finish()).toMatchObject({ keys: level.par_keys, seconds: 1.23, stars: 3 })
  })

  it("ignores keys after finishing", () => {
    const { clock } = fakeClock()
    const session = new Session(level, clock)
    session.countKeys(1)
    session.finish()
    session.countKeys(5)
    expect(session.keys).toBe(1)
  })
})

describe("daily", () => {
  const pool = ["a", "b", "c", "d", "e"]

  it("never repeats a level two days running", () => {
    const picks = Array.from({ length: 50 * pool.length }, (_, day) => pickDaily(pool, day))
    for (const [index, level] of picks.slice(1).entries()) {
      expect(level).not.toBe(picks[index])
    }
  })

  it("picks from the demo levels, sorted by id", () => {
    const ids = dailyPool(loadPacks())
    expect(ids.length).toBeGreaterThan(0)
    expect(ids).toEqual([...ids].sort())
    expect(dailyPool(demoPacks(loadPacks()))).toEqual(ids)
  })

  it("counts UTC days", () => {
    expect(dayNumber(Date.UTC(2026, 9, 30, 23, 59))).toBe(20756)
  })
})
