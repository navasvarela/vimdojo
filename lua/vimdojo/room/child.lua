-- Runs inside the clean-room child Neovim (see room.lua). It builds the level
-- from data the parent sends, checks the goal whenever the editor settles in
-- Normal mode, and reports back to the parent over RPC.
--
-- The parent starts the child with VIMDOJO_PARENT (its server address) and
-- VIMDOJO_ROOM (an id) in the environment.
local config_check = require("vimdojo.room.config_check")
local goals = require("vimdojo.goals")
local goal_views = require("vimdojo.goal_views")

local M = {}

---@class vimdojo.RoomSpec
---@field level vimdojo.Level
---@field keymaps vimdojo.Controls
---@field leader string The parent's mapleader, so <leader> means the same here.

---@type { parent: integer|nil, room: string|nil, level: vimdojo.Level|nil, buf: integer|nil, solved: boolean, augroup: integer|nil, config_check: vimdojo.ConfigCheck|nil, workspace: string|nil, check_pending: boolean }
local state = { solved = false, check_pending = false }

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

--- Also called by the replay verifier (verifier/), so replays see the same
--- options as the live room: `wrap` and `number` change what some motions do.
function M.set_ui_options()
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
  M.set_ui_options()
  notify("ready")
end

--- A buffer's file relative to the workspace, with forward slashes: the form
--- level data uses (layout leaves).
---@param buf integer
---@return string|nil
local function workspace_name(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return nil
  end
  return (vim.fn.fnamemodify(name, ":."):gsub("\\", "/"))
end

--- The loaded buffer editing `full`, if any. Files are compared by their
--- real path, which resolves symlinks (macOS /var), Windows backslashes,
--- drive-letter case and short 8.3 names alike. Workspace files always exist
--- on disk, so their real path is defined.
---@param full string
---@return integer|nil buf
local function loaded_buffer(full)
  local target = (vim.uv or vim.loop).fs_realpath(full)
  if not target then
    return nil
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if
      vim.api.nvim_buf_is_loaded(buf)
      and name ~= ""
      and (vim.uv or vim.loop).fs_realpath(name) == target
    then
      return buf
    end
  end
end

--- Each workspace file the goal reads: its buffer if loaded (unsaved edits
--- count), otherwise its contents on disk.
---@param paths string[]
---@return table<string, string[]>
local function read_files(paths)
  local files = {}
  for _, path in ipairs(paths) do
    local full = state.workspace .. "/" .. path
    local buf = loaded_buffer(full)
    if buf then
      files[path] = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    elseif vim.fn.filereadable(full) == 1 then
      files[path] = vim.fn.readfile(full)
    end
  end
  return files
end

--- The current tab as winlayout(), with each window's file (relative to the
--- workspace) in place of its id.
---@param node table
---@return vimdojo.LayoutNode
local function name_layout(node)
  if node[1] == "leaf" then
    return { "leaf", workspace_name(vim.api.nvim_win_get_buf(node[2])) or "[No Name]" }
  end
  return { node[1], vim.tbl_map(name_layout, node[2]) }
end

---@return vimdojo.Snapshot|nil
function M.snapshot()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return nil
  end
  local goal = state.level and state.level.goal
  local registers = {}
  for _, name in ipairs(goal and goals.registers(goal) or {}) do
    registers[name] = {
      lines = vim.fn.getreg(name, 1, true),
      linewise = vim.fn.getregtype(name) == "V",
    }
  end
  -- The level buffer may be hidden while the player works in another file;
  -- its cursor then can't be on a cursor_at target.
  local win = vim.fn.bufwinid(state.buf)
  return {
    lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false),
    cursor = win ~= -1 and vim.api.nvim_win_get_cursor(win) or { 0, 0 },
    registers = registers,
    config_passed = state.config_check and state.config_check:passed(),
    files = (goal and state.workspace) and read_files(goals.files(goal)) or nil,
    layout = (goal and goals.reads_layout(goal)) and name_layout(vim.fn.winlayout()) or nil,
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

--- Global, not buffer-local: in levels about files and windows the player
--- moves between buffers, and the controls must work from any of them. The
--- room is a dedicated Neovim, so nothing else is affected.
---@param keymaps vimdojo.Controls
local function map_controls(keymaps)
  for name, lhs in pairs(keymaps) do
    vim.keymap.set("n", lhs, function()
      notify("control", name)
    end, { nowait = true, silent = true, desc = "vimdojo " .. name })
  end
end

--- Coalesces bursts of events (a split fires WinNew, WinEnter, BufEnter...)
--- into one check after they settle.
local function schedule_check()
  if state.check_pending then
    return
  end
  state.check_pending = true
  vim.schedule(function()
    state.check_pending = false
    check()
  end)
end

local function watch()
  -- WinResized covers moving windows (<C-w>L, <C-w>x...), which enters,
  -- creates or closes none.
  local events = {
    "TextChanged",
    "CursorMoved",
    "BufEnter",
    "WinEnter",
    "WinClosed",
    "WinNew",
    "WinResized",
  }
  vim.api.nvim_create_autocmd(events, { group = state.augroup, callback = schedule_check })
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = state.augroup,
    pattern = "*:n",
    callback = schedule_check,
  })
end

--- Setup levels: the buffer is an init.lua, checked in the sandbox whenever
--- it settles in Normal mode. Each verdict re-runs the goal check.
---@param buf integer
---@param probes vimdojo.Probe[]
local function watch_config(buf, probes)
  vim.bo[buf].filetype = "lua"
  local checker = config_check.new(buf, probes, check)
  state.config_check = checker
  vim.api.nvim_create_autocmd("TextChanged", {
    group = state.augroup,
    buffer = buf,
    callback = function()
      checker:schedule()
    end,
  })
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = state.augroup,
    pattern = "*:n",
    callback = function()
      checker:schedule()
    end,
  })
  -- Shows what the starter config is missing before the first edit.
  checker:schedule()
end

local function stop_config_check()
  if state.config_check then
    state.config_check:stop()
    state.config_check = nil
  end
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

--- Writes the level's files into a fresh directory, makes it the working
--- directory, and edits the `open` file.
---@param level vimdojo.Level
---@return integer buf
local function workspace_buffer(level)
  local dir = vim.fn.tempname()
  for path, lines in pairs(level.files) do
    local full = dir .. "/" .. path
    vim.fn.mkdir(vim.fn.fnamemodify(full, ":h"), "p")
    vim.fn.writefile(lines, full)
  end
  vim.fn.mkdir(dir, "p")
  -- Work in the real path: tempname() can go through a symlink (macOS /var
  -- -> /private/var) or a Windows 8.3 short name (RUNNER~1). :find's **
  -- search returns long, resolved names, and completion breaks when they
  -- don't share the working directory's prefix.
  local real = (vim.uv or vim.loop).fs_realpath(dir) or dir
  vim.cmd.cd(vim.fn.fnameescape(real))
  state.workspace = vim.fn.getcwd()
  vim.cmd.edit(vim.fn.fnameescape(level.open))
  return vim.api.nvim_get_current_buf()
end

--- One tab, one window showing `keep`, and no other buffers, quickfix
--- entries, arguments or jumps left over from a previous attempt.
---@param keep integer
local function reset_editor(keep)
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  vim.api.nvim_win_set_buf(0, keep)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= keep then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  vim.fn.setqflist({}, "r")
  vim.cmd("silent! %argdelete")
  vim.cmd("clearjumps")
end

--- Ex commands that finish setting up the level (splits, quickfix lists,
--- a previous :s). A failing command is a bug in the level; the solution
--- tests catch it, so it is reported rather than aborting the load.
---@param commands string[]|nil
local function run_commands(commands)
  for _, command in ipairs(commands or {}) do
    local ok, err = pcall(vim.cmd, command)
    if not ok then
      vim.notify(
        ("vimdojo: preset command %q failed: %s"):format(command, err),
        vim.log.levels.ERROR
      )
    end
  end
end

--- (Re)builds the level from scratch: text or workspace, options, presets,
--- cursor, setup commands, target highlight, controls and goal checks. Also
--- used for reset.
---@param spec vimdojo.RoomSpec
function M.load(spec)
  vim.cmd("stopinsert")
  stop_config_check()
  -- Stop watching before tearing the editor down, so the teardown can't
  -- check (or solve) the old level.
  state.augroup = vim.api.nvim_create_augroup("vimdojo.room", { clear = true })
  state.level, state.solved = spec.level, false
  vim.g.mapleader = spec.leader

  state.workspace = nil
  local buf = spec.level.files and workspace_buffer(spec.level)
    or level_buffer(spec.level.start_text)
  reset_editor(buf)
  state.buf = buf

  apply_options(spec.level.options)
  apply_preset(spec.level, buf)
  vim.api.nvim_win_set_cursor(0, spec.level.cursor_start)
  run_commands(spec.level.preset and spec.level.preset.commands)
  goal_views.decorate(buf, spec.level.goal)
  map_controls(spec.keymaps)
  watch()
  local probes = goals.probes(spec.level.goal)
  if #probes > 0 then
    watch_config(buf, probes)
  end
  vim.cmd("nohlsearch | echo ''")
end

--- The level's buffer. Setup commands can split windows and change the
--- current buffer, so the replay verifier asks for it after `load`.
---@return integer|nil
function M.buffer()
  return state.buf
end

--- The child's message history, for diagnosing a level that doesn't solve
--- (an Ex command that errored shows up here).
---@return string
function M.messages()
  return vim.fn.execute("messages")
end

--- Stops edits once the attempt is over.
function M.freeze()
  stop_config_check()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.bo[state.buf].modifiable = false
  end
end

return M
