// Replays one key log in a clean, embedded Neovim and decides whether it
// solves the level, and in how many keys. The harness evaluates the goal
// itself (goals.ts, kept in step with goals.lua by the shared fixtures); the
// replayed Neovim is never asked whether it was solved.
import type { Level } from "../../web/src/challenges"
import { isMet } from "../../web/src/goals"
import { NvimClient } from "./rpc"
import { type LevelHandles, snapshot } from "./snapshot"

export type ReplayJob = {
  readonly level: Level
  /** One entry per counted key, in Vim notation ("d", "<Esc>", "<C-r>"). */
  readonly keys: readonly string[]
}

export type Verdict =
  | { readonly status: "solved"; readonly keys: number }
  | { readonly status: "unsolved" }
  | { readonly status: "error"; readonly reason: string }

export type ReplayOptions = {
  /** The Neovim executable. */
  readonly nvim: string
  /** The vimdojo checkout, whose Lua builds the level exactly as the room does. */
  readonly pluginDir: string
  readonly timeoutMs: number
}

// Runs before any replayed key, so the child is still trustworthy here. It
// builds the level with the room's own code, then removes the room's goal
// checks: they would try to notify a parent that doesn't exist, and the
// harness checks the goal itself.
const BOOTSTRAP = `
local plugin_dir, level = ...
vim.opt.runtimepath:prepend(plugin_dir)
local child = require("vimdojo.room.child")
child.set_ui_options()
child.load({ level = level, keymaps = {}, leader = "\\\\" })
vim.api.nvim_create_augroup("vimdojo.room", { clear = true })
local workspace = level.files and vim.fn.getcwd() or nil
return { buf = child.buffer(), workspace = workspace }
`

function isLevelHandles(value: unknown): value is { buf: number; workspace?: string } {
  return (
    typeof value === "object" &&
    value !== null &&
    "buf" in value &&
    typeof value.buf === "number" &&
    (!("workspace" in value) || typeof value.workspace === "string")
  )
}

function isNormalMode(value: unknown): boolean {
  return (
    typeof value === "object" &&
    value !== null &&
    "mode" in value &&
    value.mode === "n" &&
    "blocking" in value &&
    value.blocking === false
  )
}

async function bootstrap(
  nvim: NvimClient,
  job: ReplayJob,
  options: ReplayOptions,
): Promise<LevelHandles> {
  const handles = await nvim.request("nvim_exec_lua", [BOOTSTRAP, [options.pluginDir, job.level]])
  if (!isLevelHandles(handles)) {
    throw new Error("the level didn't load")
  }
  return { buf: handles.buf, workspace: handles.workspace }
}

/** Feeds keys one at a time; the solve is the first key after which the goal holds in Normal mode. */
async function feed(nvim: NvimClient, job: ReplayJob, level: LevelHandles): Promise<Verdict> {
  let typed = 0
  for (const key of job.keys) {
    await nvim.request("nvim_input", [key === "<" ? "<lt>" : key])
    typed += 1
    if (!isNormalMode(await nvim.request("nvim_get_mode"))) {
      continue
    }
    if (isMet(job.level.goal, await snapshot(nvim, level, job.level.goal), job.level.start_text)) {
      return { status: "solved", keys: typed }
    }
  }
  return { status: "unsolved" }
}

function timeout(ms: number): Promise<Verdict> {
  return new Promise((resolve) => {
    setTimeout(() => resolve({ status: "error", reason: `timed out after ${ms} ms` }), ms).unref()
  })
}

export async function replay(job: ReplayJob, options: ReplayOptions): Promise<Verdict> {
  const nvim = NvimClient.spawn(options.nvim, ["--clean"])
  const run = async (): Promise<Verdict> => feed(nvim, job, await bootstrap(nvim, job, options))
  try {
    return await Promise.race([run(), timeout(options.timeoutMs)])
  } catch (error) {
    return { status: "error", reason: error instanceof Error ? error.message : String(error) }
  } finally {
    nvim.close()
  }
}
