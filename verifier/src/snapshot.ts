// Reads the replayed Neovim's state through core API calls only (buffer,
// window and builtin Vimscript functions), never through Lua the child runs.
// A replayed log may redefine any Lua function in the child, including the
// room's own snapshot, but it can't change what the C API returns.
import { readFile, realpath } from "node:fs/promises"
import type { Goal, LayoutNode } from "../../web/src/challenges"
import { registersFor, type Snapshot } from "../../web/src/goals"
import type { NvimClient } from "./rpc"

/** Where the level lives in the child, captured before any key is replayed. */
export type LevelHandles = {
  readonly buf: number
  /** The workspace directory, or undefined for single-buffer levels. */
  readonly workspace: string | undefined
}

/** Workspace files a `files_equal` goal reads (see goals.files in Lua). */
function filesRead(goal: Goal): string[] {
  switch (goal.type) {
    case "files_equal":
      return Object.keys(goal.files)
    case "all_of":
      return goal.goals.flatMap(filesRead)
    default:
      return []
  }
}

function readsLayout(goal: Goal): boolean {
  switch (goal.type) {
    case "layout":
      return true
    case "all_of":
      return goal.goals.some(readsLayout)
    default:
      return false
  }
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string")
}

function isCursor(value: unknown): value is [number, number] {
  return (
    Array.isArray(value) &&
    value.length === 2 &&
    typeof value[0] === "number" &&
    typeof value[1] === "number"
  )
}

class SnapshotError extends Error {}

async function lines(nvim: NvimClient, buf: number): Promise<string[]> {
  const value = await nvim.request("nvim_buf_get_lines", [buf, 0, -1, false])
  if (!isStringArray(value)) {
    throw new SnapshotError("nvim_buf_get_lines returned no lines")
  }
  return value
}

async function call(nvim: NvimClient, fn: string, args: readonly unknown[]): Promise<unknown> {
  return nvim.request("nvim_call_function", [fn, args])
}

async function cursorOf(nvim: NvimClient, buf: number): Promise<[number, number]> {
  const win = await call(nvim, "bufwinid", [buf])
  if (typeof win !== "number" || win === -1) {
    // The level buffer is hidden, so its cursor can't be on a target.
    return [0, 0]
  }
  const cursor = await nvim.request("nvim_win_get_cursor", [win])
  if (!isCursor(cursor)) {
    throw new SnapshotError("nvim_win_get_cursor returned no position")
  }
  return cursor
}

async function registers(nvim: NvimClient, goal: Goal): Promise<Snapshot["registers"]> {
  const entries = await Promise.all(
    registersFor(goal).map(async (name) => {
      const content = await call(nvim, "getreg", [name, 1, 1])
      const type = await call(nvim, "getregtype", [name])
      return [
        name,
        { lines: isStringArray(content) ? content : [], linewise: type === "V" },
      ] as const
    }),
  )
  return Object.fromEntries(entries)
}

async function realpathOrUndefined(path: string): Promise<string | undefined> {
  try {
    return await realpath(path)
  } catch {
    return undefined
  }
}

/** Like Vim's readfile(): one entry per line, no entry for the final newline. */
async function readLines(path: string): Promise<string[] | undefined> {
  try {
    const text = await readFile(path, "utf8")
    const split = text.split("\n")
    return split.at(-1) === "" ? split.slice(0, -1) : split
  } catch {
    return undefined
  }
}

/** Each file the goal reads: its loaded buffer if any (unsaved edits count), else the disk. */
async function files(nvim: NvimClient, workspace: string, paths: readonly string[]) {
  const buffers = await nvim.request("nvim_list_bufs")
  const loaded = new Map<string, number>()
  for (const buf of Array.isArray(buffers) ? buffers : []) {
    if (typeof buf !== "number" || (await nvim.request("nvim_buf_is_loaded", [buf])) !== true) {
      continue
    }
    const name = await nvim.request("nvim_buf_get_name", [buf])
    const real =
      typeof name === "string" && name !== "" ? await realpathOrUndefined(name) : undefined
    if (real !== undefined) {
      loaded.set(real, buf)
    }
  }
  const result: Record<string, string[]> = {}
  for (const path of paths) {
    const full = `${workspace}/${path}`
    const buf = loaded.get((await realpathOrUndefined(full)) ?? full)
    const content = buf === undefined ? await readLines(full) : await lines(nvim, buf)
    if (content !== undefined) {
      result[path] = content
    }
  }
  return result
}

/** winlayout() with each window's file, relative to the working directory. */
async function namedLayout(nvim: NvimClient, node: unknown): Promise<LayoutNode> {
  if (!Array.isArray(node)) {
    throw new SnapshotError("winlayout() returned an unexpected shape")
  }
  const [kind, content] = node
  if (kind === "leaf" && typeof content === "number") {
    const buf = await nvim.request("nvim_win_get_buf", [content])
    const name = await nvim.request("nvim_buf_get_name", [buf])
    if (typeof name !== "string" || name === "") {
      return ["leaf", "[No Name]"]
    }
    const relative = await call(nvim, "fnamemodify", [name, ":."])
    return ["leaf", String(relative).replaceAll("\\", "/")]
  }
  if ((kind === "row" || kind === "col") && Array.isArray(content)) {
    const children: LayoutNode[] = []
    for (const child of content) {
      children.push(await namedLayout(nvim, child))
    }
    return [kind, children]
  }
  throw new SnapshotError(`winlayout() returned an unknown node ${String(kind)}`)
}

export async function snapshot(
  nvim: NvimClient,
  level: LevelHandles,
  goal: Goal,
): Promise<Snapshot> {
  const paths = filesRead(goal)
  return {
    lines: await lines(nvim, level.buf),
    cursor: await cursorOf(nvim, level.buf),
    registers: await registers(nvim, goal),
    files:
      paths.length > 0 && level.workspace !== undefined
        ? await files(nvim, level.workspace, paths)
        : undefined,
    layout: readsLayout(goal)
      ? await namedLayout(nvim, await call(nvim, "winlayout", []))
      : undefined,
  }
}
