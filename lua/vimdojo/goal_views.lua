-- How each goal type is explained in the level header (parent Neovim) and
-- marked in the level buffer (clean-room child). Adding a goal type means
-- adding an entry here and one in goals.lua.
local M = {}

M.namespace = vim.api.nvim_create_namespace("vimdojo.goal")

---@class vimdojo.GoalView
---@field describe fun(goal: vimdojo.Goal): string[]
---@field decorate fun(buf: integer, goal: vimdojo.Goal)

---@type table<string, vimdojo.GoalView>
local views = {
  cursor_at = {
    describe = function()
      return { "Goal: put the cursor on the highlighted character." }
    end,
    decorate = function(buf, goal)
      vim.api.nvim_buf_set_extmark(buf, M.namespace, goal.line - 1, goal.col, {
        end_row = goal.line - 1,
        end_col = goal.col + 1,
        hl_group = "VimDojoTarget",
        strict = false,
      })
    end,
  },
  buffer_equals = {
    describe = function(goal)
      local lines = { "Goal: make the text read exactly:" }
      for _, line in ipairs(goal.value) do
        table.insert(lines, "  │ " .. line)
      end
      return lines
    end,
    decorate = function() end,
  },
}

---@param goal vimdojo.Goal
---@return string[]
function M.describe(goal)
  return views[goal.type].describe(goal)
end

---@param buf integer
---@param goal vimdojo.Goal
function M.decorate(buf, goal)
  vim.api.nvim_set_hl(0, "VimDojoTarget", { link = "IncSearch", default = true })
  vim.api.nvim_buf_clear_namespace(buf, M.namespace, 0, -1)
  views[goal.type].decorate(buf, goal)
end

return M
