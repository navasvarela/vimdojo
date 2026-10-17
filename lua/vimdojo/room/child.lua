-- Runs inside the clean-room child Neovim (see room.lua). It builds the level
-- from data the parent sends, checks the goal whenever the editor settles in
-- Normal mode, and reports back to the parent over RPC.
--
-- The parent starts the child with VIMDOJO_PARENT (its server address) and
-- VIMDOJO_ROOM (an id) in the environment.
local goals = require("vimdojo.goals")
local goal_views = require("vimdojo.goal_views")

local M = {}

---@class vimdojo.RoomSpec
---@field level vimdojo.Level
---@field keymaps vimdojo.Controls
---@field leader string The parent's mapleader, so <leader> means the same here.

---@type { parent: integer|nil, room: string|nil, level: vimdojo.Level|nil, buf: integer|nil, solved: boolean, augroup: integer|nil }
local state = { solved = false }

---@param event string
---@param payload any
local function notify(event, payload)
  vim.rpcnotify(
    state.parent,
    "nvim_exec_lua",
    "require('vimdojo.room')._event(...)",
    { state.room, event, payload }
  )
end

local function set_ui_options()
  local o = vim.o
  o.laststatus = 0
  o.ruler = false
  o.showcmd = true
  o.showmode = true
  o.cmdheight = 1
  o.number = true
  o.signcolumn = "no"
  o.wrap = false
  o.termguicolors = true
  o.swapfile = false
  -- A click could move the cursor onto a cursor_at target for free.
  o.mouse = ""
  vim.opt.fillchars:append({ eob = " " })
end

--- Entry point, run once by the child's `-c` startup command.
function M.start()
  state.room = vim.env.VIMDOJO_ROOM
  state.parent = vim.fn.sockconnect("pipe", vim.env.VIMDOJO_PARENT, { rpc = true })
  -- Lua cannot ask which channel a call arrived on, so the parent finds this
  -- connection by the client name set here (see room.lua find_channel).
  vim.rpcrequest(
    state.parent,
    "nvim_set_client_info",
    "vimdojo-room-" .. state.room,
    vim.empty_dict(),
    "remote",
    vim.empty_dict(),
    vim.empty_dict()
  )
  set_ui_options()
  notify("ready")
end

---@return vimdojo.Snapshot|nil
function M.snapshot()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return nil
  end
  local win = vim.fn.bufwinid(state.buf)
  if win == -1 then
    return nil
  end
  local registers = {}
  for _, name in ipairs(state.level and goals.registers(state.level.goal) or {}) do
    registers[name] = {
      lines = vim.fn.getreg(name, 1, true),
      linewise = vim.fn.getregtype(name) == "V",
    }
  end
  return {
    lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false),
    cursor = vim.api.nvim_win_get_cursor(win),
    registers = registers,
  }
end

-- Goals are only checked in Normal mode: an edit counts as done once the
-- player leaves Insert mode, the same way the reference solutions are typed.
local function check()
  if state.solved or not state.level or vim.api.nvim_get_mode().mode ~= "n" then
    return
  end
  local snapshot = M.snapshot()
  if snapshot and goals.is_met(state.level.goal, snapshot, state.level.start_text) then
    state.solved = true
    M.freeze()
    notify("solved")
  end
end

---@param buf integer
---@param keymaps vimdojo.Controls
local function map_controls(buf, keymaps)
  for name, lhs in pairs(keymaps) do
    vim.keymap.set("n", lhs, function()
      notify("control", name)
    end, { buffer = buf, nowait = true, silent = true, desc = "vimdojo " .. name })
  end
end

---@param buf integer
local function watch(buf)
  state.augroup = vim.api.nvim_create_augroup("vimdojo.room", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "CursorMoved" }, {
    group = state.augroup,
    buffer = buf,
    callback = check,
  })
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = state.augroup,
    pattern = "*:n",
    callback = check,
  })
end

---@param lines string[]
---@return integer buf
local function level_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  -- Loading the text with undo disabled means `u` can never undo the level
  -- back to an empty buffer.
  vim.bo[buf].undolevels = -1
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].undolevels = vim.go.undolevels
  return buf
end

---@param options table<string, string|number|boolean>|nil
local function apply_options(options)
  for name, value in pairs(options or {}) do
    vim.api.nvim_set_option_value(name, value, {})
  end
end

--- Registers the goal reads start empty, so a reset never inherits a register
--- filled during the previous attempt; then the level's presets apply.
---@param level vimdojo.Level
---@param buf integer
local function apply_preset(level, buf)
  for _, name in ipairs(goals.registers(level.goal)) do
    vim.fn.setreg(name, {})
  end
  local preset = level.preset or {}
  for name, value in pairs(preset.registers or {}) do
    vim.fn.setreg(name, value, type(value) == "table" and "l" or "c")
  end
  for name, position in pairs(preset.marks or {}) do
    vim.api.nvim_buf_set_mark(buf, name, position[1], position[2], {})
  end
end

--- (Re)builds the level in a fresh buffer: text, options, presets, cursor,
--- target highlight, control mappings and goal checks. Also used for reset.
---@param spec vimdojo.RoomSpec
function M.load(spec)
  vim.cmd("stopinsert")
  state.level, state.solved = spec.level, false
  vim.g.mapleader = spec.leader

  local previous = state.buf
  local buf = level_buffer(spec.level.start_text)
  vim.api.nvim_win_set_buf(0, buf)
  if previous and previous ~= buf and vim.api.nvim_buf_is_valid(previous) then
    vim.api.nvim_buf_delete(previous, { force = true })
  end
  state.buf = buf

  apply_options(spec.level.options)
  apply_preset(spec.level, buf)
  vim.api.nvim_win_set_cursor(0, spec.level.cursor_start)
  goal_views.decorate(buf, spec.level.goal)
  map_controls(buf, spec.keymaps)
  watch(buf)
  vim.cmd("nohlsearch | echo ''")
end

--- Stops edits once the attempt is over.
function M.freeze()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.bo[state.buf].modifiable = false
  end
end

return M
