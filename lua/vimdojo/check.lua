-- Small type predicates shared by the challenge and goal validators.
local M = {}

---@param value any
---@return boolean
function M.is_integer(value)
  return type(value) == "number" and value == math.floor(value)
end

---@param value any
---@return boolean
function M.is_non_empty_string(value)
  return type(value) == "string" and value ~= ""
end

---@param value any
---@return boolean
function M.is_string_list(value)
  if type(value) ~= "table" or #value == 0 then
    return false
  end
  for _, item in ipairs(value) do
    if type(item) ~= "string" then
      return false
    end
  end
  return true
end

return M
