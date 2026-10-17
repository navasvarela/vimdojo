import { z } from "zod"

// Runtime mirror of challenges/schema.json. The JSON Schema is the contract
// (validated in CI); this parses the bundled packs into typed data at the edge.

const Lines = z.array(z.string()).min(1)

const BufferEqualsGoal = z.object({
  type: z.literal("buffer_equals"),
  value: Lines,
})

const CursorAtGoal = z.object({
  type: z.literal("cursor_at"),
  line: z.number().int().min(1),
  col: z.number().int().min(0),
  allow_edit: z.boolean().optional(),
})

const Goal = z.discriminatedUnion("type", [BufferEqualsGoal, CursorAtGoal])

const Level = z.object({
  id: z.string().min(1),
  title: z.string().min(1),
  description: z.string().min(1),
  start_text: Lines,
  /** [line, col]: 1-based line, 0-based UTF-8 byte column (Neovim's convention). */
  cursor_start: z.tuple([z.number().int().min(1), z.number().int().min(0)]),
  goal: Goal,
  par_keys: z.number().int().min(1),
  par_seconds: z.number().positive(),
  hint: z.string().min(1),
  solution: z.string().min(1),
  teaches: z.array(z.string()).min(1),
  web_demo: z.boolean().optional(),
})

const Pack = z.object({
  pack: z.string().min(1),
  title: z.string().min(1),
  description: z.string().optional(),
  order: z.number().int().min(1),
  levels: z.array(Level).min(1),
})

export type BufferEqualsGoal = z.infer<typeof BufferEqualsGoal>
export type CursorAtGoal = z.infer<typeof CursorAtGoal>
export type Goal = z.infer<typeof Goal>
export type Level = z.infer<typeof Level>
export type Pack = z.infer<typeof Pack>

/** Parses raw pack files and sorts them into curriculum order. Throws on invalid data. */
export function parsePacks(raw: readonly unknown[]): Pack[] {
  return raw.map((data) => Pack.parse(data)).sort((a, b) => a.order - b.order)
}

/** Every pack in ../challenges, bundled at build time. */
export function loadPacks(): Pack[] {
  const files = import.meta.glob<unknown>("../../challenges/[0-9]*.json", {
    eager: true,
    import: "default",
  })
  return parsePacks(Object.values(files))
}

/** Packs reduced to the levels flagged for the browser demo; empty packs are dropped. */
export function demoPacks(packs: readonly Pack[]): Pack[] {
  return packs
    .map((pack) => ({ ...pack, levels: pack.levels.filter((level) => level.web_demo === true) }))
    .filter((pack) => pack.levels.length > 0)
}

export function nextLevel(packs: readonly Pack[], levelId: string): Level | undefined {
  const levels = packs.flatMap((pack) => pack.levels)
  const index = levels.findIndex((level) => level.id === levelId)
  return index === -1 ? undefined : levels[index + 1]
}
