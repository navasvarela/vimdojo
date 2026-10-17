-- Goal checkers. Pure: they inspect a buffer snapshot and never call the
-- Neovim API, so they can be unit-tested and mirrored in the web port.
local check = require("vimdojo.check")

local M = {}

---@class vimdojo.Snapshot
---@field lines string[]
---@field cursor integer[] [line, col]: 1-based line, 0-based byte column.

---@class vimdojo.Goal
---@field type string
---@field value string[]|nil buffer_equals
---@field line integer|nil cursor_at
---@field col integer|nil cursor_at
---@field allow_edit boolean|nil cursor_at

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

---@class vimdojo.GoalKind
---@field validate fun(goal: vimdojo.Goal): string|nil
---@field is_met fun(goal: vimdojo.Goal, state: vimdojo.Snapshot, start_lines: string[]): boolean

---@type table<string, vimdojo.GoalKind>
local kinds = {
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

return M
