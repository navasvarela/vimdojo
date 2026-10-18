-- Compares what a probe expected with what the sandbox observed.
local M = {}

---@param value any
---@return string
function M.show(value)
  return vim.inspect(value, { newline = " ", indent = "" })
end

--- Errors from `vim.cmd` carry the Lua location of nvim_exec2 in Neovim's
--- runtime, which means nothing to the player; keep just "E492: ...".
---@param err any
---@return string
function M.error_message(err)
  local text = tostring(err)
  return text:match("Vim[^:]*:(E%d+:.*)$") or text
end

--- The first expected field that doesn't match, as a message for the player.
--- Fields are checked in sorted order so the message is deterministic.
---@param expected table<string, any>
---@param actual table<string, any>
---@return string|nil mismatch Nil when everything matches.
function M.mismatch(expected, actual)
  local names = vim.tbl_keys(expected)
  table.sort(names)
  for _, name in ipairs(names) do
    if not vim.deep_equal(actual[name], expected[name]) then
      return ("%s is %s, expected %s"):format(name, M.show(actual[name]), M.show(expected[name]))
    end
  end
end

return M
