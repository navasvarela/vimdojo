-- The harness itself: a room that stops answering must fail the level that
-- caused it, because a blocked RPC request would otherwise hang the whole run.
local player_mod = require("player")

local LEVEL = "basic-motions-01"
-- Long enough for the keys to pass through the terminal to the room.
local KEYS_SETTLE_MS = 500
-- Over the width where the room's command line wraps, so it ends in a prompt.
local PROMPTS = ":echo repeat('m', 100)<CR>"

---@param fn fun()
---@return string message
local function failure_of(fn)
  local ok, err = pcall(fn)
  assert.is_false(ok)
  return tostring(err)
end

describe("player", function()
  local player

  before_each(function()
    player = player_mod.spawn({ unlock_all = true })
    assert.is_true(player:start(LEVEL))
  end)

  after_each(function()
    player:stop()
  end)

  it("reads a room that is free", function()
    assert.is_table(player:snapshot().lines)
  end)

  it("names the level and shows the prompt when the room is blocked", function()
    player:type(PROMPTS)
    vim.wait(KEYS_SETTLE_MS)
    local message = failure_of(function()
      player:snapshot()
    end)
    assert.truthy(message:find(LEVEL, 1, true), message)
    assert.truthy(message:find("blocked", 1, true), message)
    assert.truthy(message:find("Press ENTER", 1, true), message)
  end)

  it("kills a player stuck on a blocked room instead of waiting forever", function()
    player:type(PROMPTS)
    vim.wait(KEYS_SETTLE_MS)
    player.rpc_timeout_ms = 500
    local message = failure_of(function()
      player:lua("return require('vimdojo.app').current().room:snapshot()")
    end)
    assert.truthy(message:find(LEVEL, 1, true), message)
    assert.truthy(message:find("did not answer", 1, true), message)
  end)

  it("still reads the room while an operator waits for its motion", function()
    player:type("d")
    vim.wait(KEYS_SETTLE_MS)
    player.rpc_timeout_ms = 2000
    assert.is_table(player:snapshot().lines)
  end)
end)
