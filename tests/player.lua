-- Drives a real Neovim the way a player would: an embedded parent instance
-- with vimdojo loaded, receiving keys through nvim_input(). Levels open their
-- clean room (a child Neovim in a terminal) inside it, so these tests exercise
-- the whole path: key capture, terminal, child mappings, goal checks, RPC.
local helpers = require("helpers")
local keys = require("vimdojo.keys")

local uv = vim.uv or vim.loop

-- Waits and the RPC watchdog count ticks of a short sleep, not elapsed time.
-- libuv's clock on macOS (mach_continuous_time) keeps running while the machine
-- sleeps, so a 5 s deadline that spans a sleep has already passed on wake. That
-- failed levels at random with "the starter config was never checked" or "room
-- never became ready" on a laptop with its lid closed, where the log appeared to
-- hang on a different level each run. A tick that spans a sleep counts once.
local WAIT_POLL_MS = 20
local WAIT_POLLS = 250
local WATCHDOG_TICK_MS = 250
-- Far longer than any request takes on a loaded CI runner, and short enough to
-- see the failure while the run is still being watched.
local DEFAULT_RPC_TIMEOUT_MS = 30000
-- After <Esc>, the child's terminal UI waits 'ttimeoutlen' (50 ms) to tell a
-- lone Escape from the start of an Alt/escape sequence. Feeding the next key
-- sooner would turn `<Esc>j` into <M-j>.
local ESC_SETTLE_MS = 120

---@class Player
---@field chan integer
---@field pid integer
---@field room_pid integer|nil Set once a level has started.
---@field level_id string|nil The level last started, named in failures.
---@field rpc_timeout_ms integer
---@field progress_path string
---@field keylog_dir string
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
  local player = setmetatable({
    chan = chan,
    pid = vim.fn.jobpid(chan),
    rpc_timeout_ms = DEFAULT_RPC_TIMEOUT_MS,
    progress_path = helpers.temp_dir() .. "/progress.json",
    keylog_dir = (setup and setup.keylog_dir) or helpers.temp_dir(),
  }, Player)
  player:lua(
    "local setup, progress_path, keylog_dir = ...;"
      .. " require('vimdojo').setup(vim.tbl_extend('force', setup,"
      .. " { progress_path = progress_path, keylog_dir = keylog_dir }))",
    setup or {},
    player.progress_path,
    player.keylog_dir
  )
  return player
end

---@param problem string
---@return string
function Player:_failure(problem)
  return ("%s: %s"):format(self.level_id or "no level started", problem)
end

--- Runs in a fast context (a timer callback), so it can only use luv.
function Player:_kill()
  if self.room_pid then
    pcall(uv.kill, self.room_pid, "sigkill")
  end
  pcall(uv.kill, self.pid, "sigkill")
end

--- vim.rpcrequest can't time out: if the player is stuck, typically inside its
--- own request to a blocked room, this would wait forever. Timers still run
--- during the wait, so a watchdog kills the processes, which ends the request.
---@param method string
---@return any result
function Player:_request(method, ...)
  local budget = math.ceil(self.rpc_timeout_ms / WATCHDOG_TICK_MS)
  local ticks, tripped = 0, false
  local watchdog = uv.new_timer()
  watchdog:start(WATCHDOG_TICK_MS, WATCHDOG_TICK_MS, function()
    ticks = ticks + 1
    if ticks >= budget and not tripped then
      tripped = true
      self:_kill()
    end
  end)
  local ok, result = pcall(vim.rpcrequest, self.chan, method, ...)
  watchdog:stop()
  watchdog:close()
  if tripped then
    local problem = "the player's Neovim did not answer %s within %g s, so it was killed;"
      .. " it is usually waiting on a room stuck at a prompt"
    error(self:_failure(problem:format(method, self.rpc_timeout_ms / 1000)), 0)
  end
  if not ok then
    error(result, 0)
  end
  return result
end

---@param code string Lua chunk; `...` holds the extra arguments.
---@return any value With RPC's vim.NIL mapped back to nil.
function Player:lua(code, ...)
  local value = self:_request("nvim_exec_lua", code, { ... })
  if value == vim.NIL then
    return nil
  end
  return value
end

---@param raw string Keys in nvim_input() notation, sent at once.
function Player:input(raw)
  self:_request("nvim_input", raw)
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

--- Polls `check` until it returns a truthy value (see WAIT_POLLS).
---@param check fun(): any
---@return any value The first truthy value, or the last one on timeout.
function Player:poll(check)
  local value
  for _ = 1, WAIT_POLLS do
    value = check()
    if value then
      return value
    end
    vim.wait(WAIT_POLL_MS)
  end
  return value
end

---@param code string Lua expression evaluated in the player's Neovim.
---@return any value The first truthy value, or the last one on timeout.
function Player:wait_for(code)
  return self:poll(function()
    return self:lua("return " .. code)
  end)
end

--- Starts a level and waits until its clean room is ready for keys.
---@param level_id string
---@return boolean ready
function Player:start(level_id)
  self.level_id = level_id
  self.room_pid = self:lua(
    "require('vimdojo.app').start(...);"
      .. " local play = require('vimdojo.app').current();"
      .. " return play and vim.fn.jobpid(play.room.job)",
    level_id
  )
  return self:wait_for("(require('vimdojo.app').current() or {}).ready") == true
end

-- A Neovim at a "Press ENTER" prompt, or anything else that waits for a key
-- outside the main loop, doesn't serve RPC requests until a key arrives, but it
-- does answer nvim_get_mode, which is handled as soon as it's read.
local ROOM_CALL = [[
local fn = ...
local play = require('vimdojo.app').current()
if not play then
  return nil
end
local mode = vim.rpcrequest(play.room.chan, 'nvim_get_mode')
if mode.blocking then
  local screen = vim.tbl_filter(function(line)
    return line:match('%S') ~= nil
  end, vim.api.nvim_buf_get_lines(play.room.buf, 0, -1, false))
  error(('the room is blocked waiting for a key (mode %q), screen:\n%s'):format(
    mode.mode,
    table.concat(screen, '\n')
  ), 0)
end
return play.room:call(fn, select(2, ...))
]]

--- Calls a function of room/child.lua in the current level's room. Fails right
--- away if the room can't answer, instead of blocking the player on it.
---@param fn string
---@return any result nil when no level is being played.
function Player:room_call(fn, ...)
  local ok, result = pcall(self.lua, self, ROOM_CALL, fn, ...)
  if not ok then
    error(self:_failure(tostring(result)), 0)
  end
  return result
end

---@return vimdojo.Snapshot|nil
function Player:snapshot()
  return self:room_call("snapshot")
end

---@param level_id string
---@return vimdojo.LevelRecord|nil
function Player:wait_for_record(level_id)
  return self:wait_for(("require('vimdojo.app').progress().levels[%q]"):format(level_id))
end

-- How long to wait for the player's Neovim to exit after asking it to quit.
local EXIT_TIMEOUT_MS = 2000

--- Quits the level first so the room's Neovim is stopped by its owner: on
--- Windows, killing the player doesn't take its terminal child with it, and
--- orphaned rooms pile up until new Neovims fail to start.
function Player:stop()
  pcall(self.lua, self, "require('vimdojo.app').quit()")
  pcall(vim.rpcnotify, self.chan, "nvim_command", "qa!")
  if vim.fn.jobwait({ self.chan }, EXIT_TIMEOUT_MS)[1] == -1 then
    vim.fn.jobstop(self.chan)
  end
end

return M
