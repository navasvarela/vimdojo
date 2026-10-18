-- Loads the player's config inside the sandbox and turns a failure into a
-- message and line number the level can point at.
local M = {}

-- The chunk name errors are reported under, so messages read "init.lua:3:
-- ..." instead of a long temporary path (Lua truncates long chunk names).
M.CHUNK_NAME = "init.lua"

---@class vimdojo.LoadError
---@field message string The first line of the error.
---@field line integer|nil The config line it points at, when known.

--- Pure: extracts the message and the innermost config line from a Lua
--- error, with or without a traceback appended.
---@param err string
---@return vimdojo.LoadError
function M.describe_error(err)
  local message = err:match("^[^\n]*")
  -- A bare chunk name, so runtime files such as vim/_init.lua don't count.
  for prefix, line in err:gmatch("(%S*)" .. vim.pesc(M.CHUNK_NAME) .. ":(%d+):") do
    if prefix == "" then
      return { message = message, line = tonumber(line) }
    end
  end
  return { message = message }
end

---@param path string
---@return vimdojo.LoadError|nil
function M.source(path)
  local file, open_err = io.open(path, "rb")
  if not file then
    return { message = "could not read the config: " .. tostring(open_err) }
  end
  local text = file:read("*a")
  file:close()
  local chunk, syntax_err = loadstring(text, "@" .. M.CHUNK_NAME)
  if not chunk then
    return M.describe_error(syntax_err)
  end
  local ok, trace = xpcall(chunk, debug.traceback)
  if not ok then
    return M.describe_error(tostring(trace))
  end
end

---@type vimdojo.LoadError|nil
M.startup_error = nil

--- Called by the sandbox's -u shim, so the config loads at the same point of
--- startup a real init.lua does (before plugins and filetype detection).
---@param path string
function M.startup(path)
  vim.env.MYVIMRC = path
  M.startup_error = M.source(path)
end

return M
