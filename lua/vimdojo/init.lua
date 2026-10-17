local M = {}

---@class vimdojo.Config
---@field unlock_all boolean Unlock every pack and level regardless of progress.
---@field window "float"|"tab" Where a level is played.
---@field progress_path string|nil Override for the progress file location (used by tests).

---@type vimdojo.Config
local defaults = {
  unlock_all = false,
  window = "float",
  progress_path = nil,
}

---@type vimdojo.Config
M.config = vim.deepcopy(defaults)

---@param opts vimdojo.Config|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

---@return string[]
function M.subcommands()
  return {}
end

---@param args string[]
function M.command(args)
  vim.notify(
    "vimdojo: not implemented yet (" .. table.concat(args, " ") .. ")",
    vim.log.levels.INFO
  )
end

return M
