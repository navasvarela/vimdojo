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

const RegisterName = z.string().regex(/^[a-z0-9"-]$/)

const RegisterContainsGoal = z.object({
  type: z.literal("register_contains"),
  register: RegisterName,
  value: Lines,
  linewise: z.boolean().optional(),
})

const AllOfGoal = z.object({
  type: z.literal("all_of"),
  get goals(): z.ZodArray<typeof Goal> {
    return z.array(Goal).min(1)
  },
})

export const PROBE_KINDS = [
  "option",
  "keys",
  "filetype",
  "command",
  "source_twice",
  "extmarks_after",
  "lua",
] as const

// Probes run only in a sandboxed Neovim, never in the browser, so the web
// keeps just what it shows (kind, description). Their exact shape is checked
// by challenges/schema.json in CI and by lua/vimdojo/probes when packs load.
const Probe = z.looseObject({
  kind: z.enum(PROBE_KINDS),
  description: z.string().min(1).optional(),
})

const ConfigProbesGoal = z.object({
  type: z.literal("config_probes"),
  probes: z.array(Probe).min(1),
})

/** A relative path inside a level's workspace (no absolute paths, no `..`). */
const WorkspacePath = z
  .string()
  .regex(/^[A-Za-z0-9_.-]+(\/[A-Za-z0-9_.-]+)*$/)
  .refine((path) => !path.split("/").some((segment) => segment === "." || segment === ".."))

/** winlayout() with workspace file names in the leaves. */
export type LayoutNode = ["leaf", string] | ["row" | "col", LayoutNode[]]

export const LayoutNodeSchema: z.ZodType<LayoutNode> = z.lazy(() =>
  z.union([
    z.tuple([z.literal("leaf"), WorkspacePath]),
    z.tuple([z.enum(["row", "col"]), z.array(LayoutNodeSchema).min(2)]),
  ]),
)

const FilesEqualGoal = z.object({
  type: z.literal("files_equal"),
  files: z.record(WorkspacePath, Lines),
})

const LayoutGoal = z.object({
  type: z.literal("layout"),
  layout: LayoutNodeSchema,
})

const Goal = z.discriminatedUnion("type", [
  BufferEqualsGoal,
  CursorAtGoal,
  RegisterContainsGoal,
  AllOfGoal,
  ConfigProbesGoal,
  FilesEqualGoal,
  LayoutGoal,
])

const Position = z.tuple([z.number().int().min(1), z.number().int().min(0)])

const Preset = z.object({
  /** A string is charwise; an array of lines is linewise. */
  registers: z.record(RegisterName, z.union([z.string(), Lines])).optional(),
  marks: z.record(z.string().regex(/^[a-z]$/), Position).optional(),
  /** Ex commands run after the level is built. Neovim only. */
  commands: z.array(z.string().min(1)).min(1).optional(),
})

export const TRACKS = ["motions", "usage", "setup"] as const
export type Track = (typeof TRACKS)[number]

const LevelData = z.object({
  id: z.string().min(1),
  title: z.string().min(1),
  description: z.string().min(1),
  /** Either start_text, or workspace files plus the one to open. */
  start_text: Lines.optional(),
  files: z.record(WorkspacePath, Lines).optional(),
  open: z.string().optional(),
  /** [line, col]: 1-based line, 0-based UTF-8 byte column (Neovim's convention). */
  cursor_start: Position,
  goal: Goal,
  par_keys: z.number().int().min(1),
  par_seconds: z.number().positive(),
  hint: z.string().min(1),
  solution: z.string().min(1),
  teaches: z.array(z.string()).min(1),
  web_demo: z.boolean().optional(),
  requires: z.object({ nvim: z.string().regex(/^\d+\.\d+(\.\d+)?$/) }).optional(),
  options: z.record(z.string(), z.union([z.string(), z.number(), z.boolean()])).optional(),
  preset: Preset.optional(),
})

// Mirrors challenges.level_text in Lua: a workspace level starts with the text
// of its open file, so every level has start_text after parsing.
const Level = LevelData.transform((level, ctx) => {
  const opened = level.open === undefined ? undefined : level.files?.[level.open]
  const startText = level.start_text ?? opened
  if (startText === undefined) {
    ctx.addIssue({ code: "custom", message: "a level needs start_text, or files and open" })
    return z.NEVER
  }
  return { ...level, start_text: startText }
})

const Pack = z.object({
  pack: z.string().min(1),
  title: z.string().min(1),
  description: z.string().optional(),
  order: z.number().int().min(1),
  track: z.enum(TRACKS).default("motions"),
  levels: z.array(Level).min(1),
})

export type BufferEqualsGoal = z.infer<typeof BufferEqualsGoal>
export type CursorAtGoal = z.infer<typeof CursorAtGoal>
export type RegisterContainsGoal = z.infer<typeof RegisterContainsGoal>
export type ConfigProbesGoal = z.infer<typeof ConfigProbesGoal>
export type FilesEqualGoal = z.infer<typeof FilesEqualGoal>
export type LayoutGoal = z.infer<typeof LayoutGoal>
export type Preset = z.infer<typeof Preset>
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
