-- Sandbox-side helpers shared by the probes: a real file to edit, feeding
-- keys the way a player types them, and reading back editor state.
local compare = require("vimdojo.probes.compare")

local M = {}

local next_id = 0

--- Edits a new file holding `lines` in the current window. It is a real file
--- so that mappings and autocommands that write (`:w`, BufWritePre) work.
---@param lines string[]|nil Defaults to one empty line.
---@param cursor integer[]|nil [line, col]; defaults to the first character.
---@return integer buf
function M.open(lines, cursor)
  next_id = next_id + 1
  local path = ("%s-fixture-%d.txt"):format(vim.fn.tempname(), next_id)
  vim.fn.writefile(lines or { "" }, path)
  vim.cmd.edit(vim.fn.fnameescape(path))
  if cursor then
    pcall(vim.api.nvim_win_set_cursor, 0, cursor)
  end
  return vim.api.nvim_get_current_buf()
end

--- `<Leader>` only means something inside mappings, so feeding it literally
--- would type the characters. Expand it to the leader the config chose.
---@param notation string
---@return string
local function expand_leaders(notation)
  local localleader = vim.g.maplocalleader or "\\"
  local leader = vim.g.mapleader or "\\"
  return (
    notation
      :gsub("<[Ll]ocal[Ll]eader>", function()
        return localleader
      end)
      :gsub("<[Ll]eader>", function()
        return leader
      end)
  )
end

--- Types `notation` as if typed by the player (mappings apply) and runs it to
--- completion. Insert mode is left at the end.
---@param notation string Key notation, e.g. "yy" or "<leader>w".
---@return string|nil err The last error message the keys produced, if any.
function M.feed(notation)
  local keys = vim.api.nvim_replace_termcodes(expand_leaders(notation), true, true, true)
  vim.v.errmsg = ""
  local ok, err = pcall(vim.api.nvim_feedkeys, keys, "tx", false)
  if not ok then
    return compare.error_message(err)
  end
  if vim.v.errmsg ~= "" then
    return vim.v.errmsg
  end
end

--- Editor state the `keys` probe can assert on, read from the current window.
---@return table<string, any>
function M.state()
  return {
    lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
    cursor = vim.api.nvim_win_get_cursor(0),
    modified = vim.bo.modified,
    hlsearch = vim.v.hlsearch == 1,
    windows = #vim.api.nvim_tabpage_list_wins(0),
  }
end

--- The effective value of each option for the current buffer and window.
---@param names string[]
---@return table<string, any>
function M.options(names)
  local values = {}
  for _, name in ipairs(names) do
    values[name] = vim.api.nvim_get_option_value(name, {})
  end
  return values
end

return M
