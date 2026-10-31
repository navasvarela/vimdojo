// Adversarial checks for the replay: logs that are too short, too long,
// hostile to the harness, or that never finish. Needs `nvim` on PATH.
import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { fileURLToPath } from "node:url"
import type { Level } from "../../web/src/challenges"
import { splitNotation } from "../../web/src/keys"
import { parsePacks } from "../../web/src/challenges"
import { readPacks } from "./packs"
import { replay, type ReplayOptions } from "./replay"
import { NvimClient, NvimError } from "./rpc"

const ROOT = fileURLToPath(new URL("../..", import.meta.url))
const OPTIONS: ReplayOptions = {
  nvim: process.env["NVIM"] ?? "nvim",
  pluginDir: ROOT,
  timeoutMs: 10_000,
}
const LEVELS = new Map(
  readPacks(`${ROOT}challenges`)
    .flatMap((pack) => pack.levels)
    .map((level) => [level.id, level]),
)

function level(id: string): Level {
  const found = LEVELS.get(id)
  if (found === undefined) {
    throw new Error(`no level ${id}`)
  }
  return found
}

const replayKeys = (id: string, notation: string, options = OPTIONS) =>
  replay({ level: level(id), keys: splitNotation(notation) }, options)

describe("replay", () => {
  it("doesn't solve a log one key short", async () => {
    assert.deepEqual(await replayKeys("basic-motions-01", "jjjl"), { status: "unsolved" })
  })

  it("counts keys up to the solve and ignores the rest", async () => {
    assert.deepEqual(await replayKeys("operate-01", "ffdwjjjk"), { status: "solved", keys: 4 })
  })

  it("solves with a longer route and counts all of it", async () => {
    assert.deepEqual(await replayKeys("basic-motions-01", "lljjhjl"), { status: "solved", keys: 7 })
  })

  it("lets :lua reach the goal, at the cost of every key typed", async () => {
    const notation = ":lua vim.api.nvim_win_set_cursor(0, {4, 2})<CR>"
    assert.deepEqual(await replayKeys("basic-motions-01", notation), {
      status: "solved",
      keys: splitNotation(notation).length,
    })
  })

  it("refuses requests from the replayed Neovim and keeps going", async () => {
    // Channel 1 is the --embed stdio channel back to the harness.
    const hostile = ':lua pcall(vim.rpcrequest, 1, "nvim_exec_lua", "os.exit(1)", {})<CR>'
    const verdict = await replayKeys("basic-motions-01", `${hostile}jjjll`)
    assert.deepEqual(verdict, { status: "solved", keys: splitNotation(hostile).length + 5 })
  })

  it("survives garbage on the reply pipe, without crediting a solve", async () => {
    const hostile = ':lua io.stdout:write("garbage on the pipe"); io.stdout:flush()<CR>'
    const verdict = await replayKeys("basic-motions-01", hostile)
    assert.notEqual(verdict.status, "solved")
    assert.deepEqual(await replayKeys("basic-motions-01", "jjjll"), { status: "solved", keys: 5 })
  })

  it("can't fake the goal by redefining the room's Lua", async () => {
    const forge =
      ':lua package.loaded["vimdojo.room.child"].snapshot = function() return {} end<CR>'
    assert.deepEqual(await replayKeys("operate-01", `${forge}j`), { status: "unsolved" })
  })

  it("times out a log that never returns control", async () => {
    const verdict = await replayKeys("basic-motions-01", ":lua while true do end<CR>", {
      ...OPTIONS,
      timeoutMs: 1000,
    })
    assert.equal(verdict.status, "error")
  })

  it("reports a log that quits Neovim as an error", async () => {
    const verdict = await replayKeys("basic-motions-01", ":qa!<CR>jjjll")
    assert.equal(verdict.status, "error")
  })

  it("survives writing to a Neovim that has quit", async () => {
    // The EPIPE this provokes used to crash the process, batch and all.
    for (let round = 0; round < 5; round++) {
      const nvim = NvimClient.spawn(OPTIONS.nvim, ["--clean"])
      await nvim.request("nvim_input", [":qa!<CR>"])
      await assert.rejects(async () => {
        for (let write = 0; write < 200; write++) {
          await nvim.request("nvim_get_mode")
        }
      }, NvimError)
      await assert.rejects(nvim.request("nvim_get_mode"), NvimError)
      nvim.close()
    }
  })

  it("replays unusual keys as the plugin logs them", async () => {
    // Exactly what the plugin logs for these: keytrans() names only space and
    // "<". No reference solution types "|", "\\" or non-ASCII text.
    const [pack] = parsePacks([
      {
        pack: "p",
        title: "P",
        order: 1,
        levels: [
          {
            id: "special-keys",
            title: "t",
            description: "d",
            start_text: ["x"],
            cursor_start: [1, 0],
            goal: { type: "buffer_equals", value: [" <|\\éx"] },
            par_keys: 7,
            par_seconds: 1,
            hint: "h",
            solution: "i",
            teaches: ["i"],
          },
        ],
      },
    ])
    const level = pack?.levels[0]
    if (level === undefined) {
      throw new Error("the level didn't parse")
    }
    const keys = ["i", "<Space>", "<lt>", "|", "\\", "é", "<Esc>"]
    assert.deepEqual(await replay({ level, keys }, OPTIONS), { status: "solved", keys: 7 })
  })

  it("checks workspace files and window layouts", async () => {
    assert.deepEqual(await replayKeys("windows-01", "<C-w>v"), { status: "solved", keys: 2 })
    assert.deepEqual(await replayKeys("project-01", "gfjflal<Esc>"), { status: "solved", keys: 8 })
  })
})
