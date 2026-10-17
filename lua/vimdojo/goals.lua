-- Goal checkers. Pure: they inspect a buffer snapshot and never call the
-- Neovim API, so they can be unit-tested and mirrored in the web port.
local check = require("vimdojo.check")

local M = {}

---@class vimdojo.Register
---@field lines string[]
---@field linewise boolean

---@class vimdojo.Snapshot
---@field lines string[]
---@field cursor integer[] [line, col]: 1-based line, 0-based byte column.
---@field registers table<string, vimdojo.Register>|nil Only those the goal reads (see M.registers).

---@class vimdojo.Goal
---@field type string
---@field value string[]|nil buffer_equals, register_contains
---@field line integer|nil cursor_at
---@field col integer|nil cursor_at
---@field allow_edit boolean|nil cursor_at
---@field register string|nil register_contains
---@field linewise boolean|nil register_contains
---@field goals vimdojo.Goal[]|nil all_of

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

local kinds

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
      for _, inner in ipairs(goal.goals) do
        local kind = kinds[inner.type]
        if kind.registers then
          kind.registers(inner, into)
        end
      end
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
  local kind = kinds[goal.type]
  if kind and kind.registers then
    kind.registers(goal, names)
  end
  local list = vim.tbl_keys(names)
  table.sort(list)
  return list
end

return M
