-- Global Terminal-mode mappings would intercept keys meant for the level in
-- the clean room. A common one maps <Esc> to leave Terminal mode, which would
-- make <Esc> unusable inside the level. They are removed while a level is
-- played and put back afterwards.
local M = {}

--- Removes every global Terminal-mode mapping.
---@return fun() restore Reinstates the removed mappings. Safe to call once.
function M.suspend()
  local saved = vim.api.nvim_get_keymap("t")
  for _, map in ipairs(saved) do
    pcall(vim.keymap.del, "t", map.lhs)
  end
  return function()
    for _, map in ipairs(saved) do
      pcall(vim.fn.mapset, "t", false, map)
    end
  end
end

return M
