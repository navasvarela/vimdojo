-- Validators for the fields probes share. Each returns an error message, or
-- nil when the field is valid.
local check = require("vimdojo.check")

local M = {}

---@param probe table
---@param field string
---@return string|nil
function M.string(probe, field)
  if not check.is_non_empty_string(probe[field]) then
    return field .. " must be a non-empty string"
  end
end

---@param probe table
---@param field string
---@return string|nil
function M.optional_lines(probe, field)
  if probe[field] ~= nil and not check.is_string_list(probe[field]) then
    return field .. " must be a non-empty array of strings"
  end
end

---@param probe table
---@return string|nil
function M.optional_cursor(probe)
  if probe.cursor ~= nil and not check.is_position(probe.cursor) then
    return "cursor must be [line, col]"
  end
end

--- An object of option names to the values they must have.
---@param probe table
---@param field string
---@return string|nil
function M.options(probe, field)
  local options = probe[field]
  if type(options) ~= "table" or next(options) == nil then
    return field .. " must be a non-empty object of option values"
  end
  for name, value in pairs(options) do
    if not check.is_option_name(name) then
      return ("%s: unknown option %q"):format(field, tostring(name))
    end
    local kind = type(value)
    if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then
      return ("%s.%s must be a string, number or boolean"):format(field, name)
    end
  end
end

---@param options table<string, any>
---@return string "shiftwidth=4, expandtab=true"
function M.format_options(options)
  local parts = {}
  for name, value in pairs(options) do
    table.insert(parts, ("%s=%s"):format(name, tostring(value)))
  end
  table.sort(parts)
  return table.concat(parts, ", ")
end

return M
