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

--- A [line, col] pair: 1-based line, 0-based byte column.
---@param value any
---@return boolean
function M.is_position(value)
  return type(value) == "table"
    and #value == 2
    and M.is_integer(value[1])
    and M.is_integer(value[2])
    and value[1] >= 1
    and value[2] >= 0
end

--- Whether Neovim knows an option by this name, so a typo in a level fails
--- validation instead of silently not applying.
---@param name any
---@return boolean
function M.is_option_name(name)
  return type(name) == "string" and (pcall(vim.api.nvim_get_option_info2, name, {}))
end

--- A relative path inside a level's workspace: no absolute paths, no `..`,
--- no empty segments, so writing it can never escape the workspace.
---@param value any
---@return boolean
function M.is_workspace_path(value)
  if type(value) ~= "string" or value == "" or value:find("^[/\\]") or value:find("\\") then
    return false
  end
  for segment in (value .. "/"):gmatch("([^/]*)/") do
    if segment == "" or segment == ".." or segment == "." or not segment:match("^[%w_%-%.]+$") then
      return false
    end
  end
  return true
end

return M
