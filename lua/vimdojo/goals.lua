-- Goal checkers. Pure: they inspect a buffer snapshot and never call the
-- Neovim API, so they can be unit-tested and mirrored in the web port.
local check = require("vimdojo.check")
local probes = require("vimdojo.probes")

local M = {}

---@class vimdojo.Register
---@field lines string[]
---@field linewise boolean

---@class vimdojo.Snapshot
---@field lines string[]
---@field cursor integer[] [line, col]: 1-based line, 0-based byte column.
---@field registers table<string, vimdojo.Register>|nil Only those the goal reads (see M.registers).
---@field config_passed boolean|nil Setup levels: the sandbox verdict for the current text, nil until there is one.
---@field files table<string, string[]>|nil Workspace files the goal reads, path -> lines (see M.files).
---@field layout vimdojo.LayoutNode|nil The current tab's windows, when the goal reads them (see M.reads_layout).

---@class vimdojo.Goal
---@field type string
---@field value string[]|nil buffer_equals, register_contains
---@field line integer|nil cursor_at
---@field col integer|nil cursor_at
---@field allow_edit boolean|nil cursor_at
---@field register string|nil register_contains
---@field linewise boolean|nil register_contains
---@field goals vimdojo.Goal[]|nil all_of
---@field probes vimdojo.Probe[]|nil config_probes
---@field files table<string, string[]>|nil files_equal
---@field layout vimdojo.LayoutNode|nil layout

--- A window layout in winlayout() shape, with files instead of window ids:
--- `{ "leaf", "main.lua" }`, `{ "row", { node, ... } }` or `{ "col", { node, ... } }`.
---@alias vimdojo.LayoutNode table

---@param a string[]
---@param b string[]
---@return boolean
local function lines_equal(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

-- Registers a goal may name: the named registers, the unnamed one, and the
-- numbered and small-delete registers players learn about.
local REGISTER_PATTERN = '^[a-z0-9"%-]$'

---@class vimdojo.GoalKind
---@field validate fun(goal: vimdojo.Goal): string|nil
---@field is_met fun(goal: vimdojo.Goal, state: vimdojo.Snapshot, start_lines: string[]): boolean
---@field registers (fun(goal: vimdojo.Goal, into: table<string, true>))|nil
---@field probes (fun(goal: vimdojo.Goal, into: vimdojo.Probe[]))|nil
---@field files (fun(goal: vimdojo.Goal, into: table<string, true>))|nil
---@field layout (fun(goal: vimdojo.Goal, into: { needed: boolean }))|nil

local kinds

---@param node any
---@return string|nil err
local function layout_error(node)
  if type(node) ~= "table" then
    return "layout nodes must be arrays"
  end
  if node[1] == "leaf" then
    if not check.is_workspace_path(node[2]) then
      return 'a leaf names a workspace file, e.g. ["leaf", "main.lua"]'
    end
    return nil
  end
  if node[1] ~= "row" and node[1] ~= "col" then
    return 'layout nodes start with "leaf", "row" or "col"'
  end
  if type(node[2]) ~= "table" or #node[2] < 2 then
    return "a row or col holds at least two nodes"
  end
  for _, child in ipairs(node[2]) do
    local err = layout_error(child)
    if err then
      return err
    end
  end
end

---@param a vimdojo.LayoutNode
---@param b vimdojo.LayoutNode
---@return boolean
local function layout_equal(a, b)
  if type(a) ~= "table" or type(b) ~= "table" or a[1] ~= b[1] then
    return false
  end
  if a[1] == "leaf" then
    return a[2] == b[2]
  end
  if #a[2] ~= #b[2] then
    return false
  end
  for i = 1, #a[2] do
    if not layout_equal(a[2][i], b[2][i]) then
      return false
    end
  end
  return true
end

--- Calls each inner goal's `hook` (registers, probes, files, layout), for
--- composite goals.
---@param hook "registers"|"probes"|"files"|"layout"
---@param goals vimdojo.Goal[]
---@param into table
local function gather(hook, goals, into)
  for _, inner in ipairs(goals) do
    local collect = kinds[inner.type][hook]
    if collect then
      collect(inner, into)
    end
  end
end

---@type table<string, vimdojo.GoalKind>
kinds = {
  buffer_equals = {
    validate = function(goal)
      if not check.is_string_list(goal.value) then
        return "value must be a non-empty array of strings"
      end
    end,
    is_met = function(goal, state)
      return lines_equal(state.lines, goal.value)
    end,
  },

  cursor_at = {
    validate = function(goal)
      if not (check.is_integer(goal.line) and goal.line >= 1) then
        return "line must be an integer >= 1"
      end
      if not (check.is_integer(goal.col) and goal.col >= 0) then
        return "col must be an integer >= 0"
      end
      if goal.allow_edit ~= nil and type(goal.allow_edit) ~= "boolean" then
        return "allow_edit must be a boolean"
      end
    end,
    is_met = function(goal, state, start_lines)
      local on_target = state.cursor[1] == goal.line and state.cursor[2] == goal.col
      return on_target and (goal.allow_edit == true or lines_equal(state.lines, start_lines))
    end,
  },

  register_contains = {
    validate = function(goal)
      if type(goal.register) ~= "string" or not goal.register:match(REGISTER_PATTERN) then
        return 'register must be one of a-z, 0-9, " or -'
      end
      if not check.is_string_list(goal.value) then
        return "value must be a non-empty array of strings"
      end
      if goal.linewise ~= nil and type(goal.linewise) ~= "boolean" then
        return "linewise must be a boolean"
      end
    end,
    is_met = function(goal, state)
      local register = state.registers and state.registers[goal.register]
      if not register or not lines_equal(register.lines, goal.value) then
        return false
      end
      return goal.linewise == nil or goal.linewise == register.linewise
    end,
    registers = function(goal, into)
      into[goal.register] = true
    end,
  },

  all_of = {
    validate = function(goal)
      if type(goal.goals) ~= "table" or #goal.goals == 0 then
        return "goals must be a non-empty array"
      end
      for index, inner in ipairs(goal.goals) do
        local err = M.validate(inner)
        if err then
          return ("goals[%d]: %s"):format(index, err)
        end
      end
    end,
    is_met = function(goal, state, start_lines)
      for _, inner in ipairs(goal.goals) do
        if not M.is_met(inner, state, start_lines) then
          return false
        end
      end
      return true
    end,
    registers = function(goal, into)
      gather("registers", goal.goals, into)
    end,
    probes = function(goal, into)
      gather("probes", goal.goals, into)
    end,
    files = function(goal, into)
      gather("files", goal.goals, into)
    end,
    layout = function(goal, into)
      gather("layout", goal.goals, into)
    end,
  },

  -- Usage levels with a workspace of real files. The snapshot carries each
  -- file's buffer if it is loaded, its contents on disk otherwise, so saving
  -- is not required.
  files_equal = {
    validate = function(goal)
      if type(goal.files) ~= "table" or next(goal.files) == nil then
        return "files must be an object of path -> lines"
      end
      for path, lines in pairs(goal.files) do
        if not check.is_workspace_path(path) then
          return ("files: %q is not a relative workspace path"):format(tostring(path))
        end
        if not check.is_string_list(lines) then
          return ("files.%s must be a non-empty array of lines"):format(path)
        end
      end
    end,
    is_met = function(goal, state)
      for path, lines in pairs(goal.files) do
        local actual = state.files and state.files[path]
        if not actual or not lines_equal(actual, lines) then
          return false
        end
      end
      return true
    end,
    files = function(goal, into)
      for path in pairs(goal.files) do
        into[path] = true
      end
    end,
  },

  -- The current tab's window layout, as winlayout() with file names.
  layout = {
    validate = function(goal)
      return layout_error(goal.layout)
    end,
    is_met = function(goal, state)
      return state.layout ~= nil and layout_equal(goal.layout, state.layout)
    end,
    layout = function(_, into)
      into.needed = true
    end,
  },

  -- Setup levels. The probes run in a sandboxed Neovim (sandbox.lua), which
  -- is asynchronous, so the room runs them and records the verdict in the
  -- snapshot; checking the goal stays a pure lookup.
  config_probes = {
    validate = function(goal)
      return probes.validate_list(goal.probes)
    end,
    is_met = function(_, state)
      return state.config_passed == true
    end,
    probes = function(goal, into)
      vim.list_extend(into, goal.probes)
    end,
  },
}

---@param goal any
---@return string|nil err Why the goal is malformed, or nil when it is valid.
function M.validate(goal)
  if type(goal) ~= "table" then
    return "goal must be an object"
  end
  local kind = kinds[goal.type]
  if not kind then
    return ("unknown goal type %q"):format(tostring(goal.type))
  end
  -- Parenthesised so a validator that returns nothing still yields one nil.
  return (kind.validate(goal))
end

--- Callers must pass a goal that `validate` accepted; challenge loading
--- guarantees this for every level.
---@param goal vimdojo.Goal
---@param state vimdojo.Snapshot
---@param start_lines string[] The level's starting text, for goals that forbid edits.
---@return boolean
function M.is_met(goal, state, start_lines)
  local kind = kinds[goal.type]
  assert(kind, "goal type was not validated: " .. tostring(goal.type))
  return kind.is_met(goal, state, start_lines)
end

--- The registers a snapshot must capture for `goal` to be checked.
--- Callers must pass a goal that `validate` accepted.
---@param goal vimdojo.Goal
---@return string[]
function M.registers(goal)
  local names = {}
  gather("registers", { goal }, names)
  local list = vim.tbl_keys(names)
  table.sort(list)
  return list
end

--- Every probe the goal runs against the player's config, in order. Empty
--- for goals that aren't about a config. Callers must pass a validated goal.
---@param goal vimdojo.Goal
---@return vimdojo.Probe[]
function M.probes(goal)
  local list = {}
  gather("probes", { goal }, list)
  return list
end

--- The workspace files a snapshot must capture for `goal`, sorted.
---@param goal vimdojo.Goal
---@return string[]
function M.files(goal)
  local paths = {}
  gather("files", { goal }, paths)
  local list = vim.tbl_keys(paths)
  table.sort(list)
  return list
end

--- Whether a snapshot must capture the window layout for `goal`.
---@param goal vimdojo.Goal
---@return boolean
function M.reads_layout(goal)
  local into = { needed = false }
  gather("layout", { goal }, into)
  return into.needed
end

return M
