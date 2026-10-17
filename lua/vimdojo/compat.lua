-- Which levels this Neovim can run. Levels declare `requires = { nvim =
-- "0.11" }` when they rely on newer defaults or APIs. Pure functions; the
-- running version is passed in.
local M = {}

---@class vimdojo.Version
---@field major integer
---@field minor integer
---@field patch integer

---@param text string "0.11" or "0.11.2"
---@return vimdojo.Version|nil
function M.parse(text)
  if type(text) ~= "string" then
    return nil
  end
  local major, minor, patch = text:match("^(%d+)%.(%d+)%.?(%d*)$")
  if not major then
    return nil
  end
  return { major = tonumber(major), minor = tonumber(minor), patch = tonumber(patch) or 0 }
end

---@param required vimdojo.Version
---@param current vimdojo.Version
---@return boolean
function M.at_least(required, current)
  if current.major ~= required.major then
    return current.major > required.major
  end
  if current.minor ~= required.minor then
    return current.minor > required.minor
  end
  return current.patch >= required.patch
end

---@param level vimdojo.Level
---@param current vimdojo.Version
---@return boolean
function M.supports(level, current)
  local required = level.requires and M.parse(level.requires.nvim)
  return required == nil or M.at_least(required, current)
end

---@return vimdojo.Version
function M.running()
  local v = vim.version()
  return { major = v.major, minor = v.minor, patch = v.patch }
end

return M
