-- Drives a real Neovim the way a player would: an embedded parent instance
-- with vimdojo loaded, receiving keys through nvim_input(). Levels open their
-- clean room (a child Neovim in a terminal) inside it, so these tests exercise
-- the whole path: key capture, terminal, child mappings, goal checks, RPC.
local helpers = require("helpers")
local keys = require("vimdojo.keys")

local TIMEOUT_MS = 5000
-- After <Esc>, the child's terminal UI waits 'ttimeoutlen' (50 ms) to tell a
-- lone Escape from the start of an Alt/escape sequence. Feeding the next key
-- sooner would turn `<Esc>j` into <M-j>.
local ESC_SETTLE_MS = 120

---@class Player
---@field chan integer
---@field progress_path string
local Player = {}
Player.__index = Player

local M = {}

---@param setup table|nil Extra vimdojo.setup() options.
---@return Player
function M.spawn(setup)
  local chan = vim.fn.jobstart({
    vim.v.progpath,
    "--embed",
    "--headless",
    "--noplugin",
    "-u",
    helpers.root .. "/tests/minimal_init.lua",
  }, { rpc = true })
  local player =
    setmetatable({ chan = chan, progress_path = helpers.temp_dir() .. "/progress.json" }, Player)
  player:lua(
    "require('vimdojo').setup(vim.tbl_extend('force', ..., { progress_path = select(2, ...) }))",
    setup or {},
    player.progress_path
  )
  return player
end

---@param code string Lua chunk; `...` holds the extra arguments.
---@return any value With RPC's vim.NIL mapped back to nil.
function Player:lua(code, ...)
  local value = vim.rpcrequest(self.chan, "nvim_exec_lua", code, { ... })
  if value == vim.NIL then
    return nil
  end
  return value
end

---@param raw string Keys in nvim_input() notation, sent at once.
function Player:input(raw)
  vim.rpcrequest(self.chan, "nvim_input", raw)
end

--- Types key notation one key at a time, pausing after <Esc> (see
--- ESC_SETTLE_MS).
---@param notation string
function Player:type(notation)
  for _, key in ipairs(keys.split(notation)) do
    self:input(key == "<" and "<lt>" or key)
    if key == "<Esc>" then
      vim.wait(ESC_SETTLE_MS)
    end
  end
end

---@param code string Lua expression evaluated in the player's Neovim.
---@return any value The first truthy value, or nil on timeout.
function Player:wait_for(code)
  local value
  vim.wait(TIMEOUT_MS, function()
    value = self:lua("return " .. code)
    return value ~= nil and value ~= false
  end, 20)
  return value
end

--- Starts a level and waits until its clean room is ready for keys.
---@param level_id string
---@return boolean ready
function Player:start(level_id)
  self:lua("require('vimdojo.app').start(...)", level_id)
  return self:wait_for("(require('vimdojo.app').current() or {}).ready") == true
end

---@return vimdojo.Snapshot|nil
function Player:snapshot()
  return self:lua("return require('vimdojo.app').current().room:snapshot()")
end

---@param level_id string
---@return vimdojo.LevelRecord|nil
function Player:wait_for_record(level_id)
  return self:wait_for(("require('vimdojo.app').progress().levels[%q]"):format(level_id))
end

function Player:stop()
  vim.fn.jobstop(self.chan)
end

return M
