-- How each goal type is explained in the level header (parent Neovim) and
-- marked in the level buffer (clean-room child). Adding a goal type means
-- adding an entry here and one in goals.lua.
local probes = require("vimdojo.probes")

local M = {}

M.namespace = vim.api.nvim_create_namespace("vimdojo.goal")

---@class vimdojo.GoalView
---@field describe fun(goal: vimdojo.Goal): string[]
---@field decorate fun(buf: integer, goal: vimdojo.Goal)
---@field extra_rows (fun(goal: vimdojo.Goal): integer)|nil Room rows beyond the start text, for goals that grow it.

local views

---@type table<string, vimdojo.GoalView>
views = {
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
  register_contains = {
    describe = function(goal)
      local kind = ""
      if goal.linewise ~= nil then
        kind = goal.linewise and " (linewise)" or " (charwise)"
      end
      local lines = { ('Goal: register "%s" must hold%s:'):format(goal.register, kind) }
      for _, line in ipairs(goal.value) do
        table.insert(lines, "  │ " .. line)
      end
      return lines
    end,
    decorate = function() end,
  },
  all_of = {
    describe = function(goal)
      local lines = {}
      for _, inner in ipairs(goal.goals) do
        vim.list_extend(lines, views[inner.type].describe(inner))
      end
      return lines
    end,
    decorate = function(buf, goal)
      for _, inner in ipairs(goal.goals) do
        views[inner.type].decorate(buf, inner)
      end
    end,
    extra_rows = function(goal)
      local rows = 0
      for _, inner in ipairs(goal.goals) do
        rows = math.max(rows, M.extra_rows(inner))
      end
      return rows
    end,
  },
  files_equal = {
    describe = function(goal)
      local lines = { "Goal: make the files read exactly:" }
      local paths = vim.tbl_keys(goal.files)
      table.sort(paths)
      for _, path in ipairs(paths) do
        table.insert(lines, "  " .. path)
        for _, line in ipairs(goal.files[path]) do
          table.insert(lines, "  │ " .. line)
        end
      end
      return lines
    end,
    decorate = function() end,
    -- Several files may end up side by side in splits.
    extra_rows = function()
      return 10
    end,
  },
  layout = {
    describe = function(goal)
      return { "Goal: arrange the windows like this:", "  " .. M.render_layout(goal.layout, true) }
    end,
    decorate = function() end,
    extra_rows = function()
      return 10
    end,
  },
  config_probes = {
    describe = function(goal)
      local lines = { "Goal: make this init.lua pass every check:" }
      for _, probe in ipairs(goal.probes) do
        table.insert(lines, "  • " .. probes.describe(probe))
      end
      table.insert(
        lines,
        "Checks run in a fresh Neovim when you pause in Normal mode; problems show in the editor."
      )
      return lines
    end,
    decorate = function() end,
    -- Players add lines to a config; leave room so it doesn't scroll at once.
    extra_rows = function()
      return 6
    end,
  },
}

--- A one-line sketch of a window layout: `a.lua │ b.lua` for side by side,
--- `a.lua ─ b.lua` for stacked, parenthesized when nested.
---@param node vimdojo.LayoutNode
---@param top boolean|nil
---@return string
function M.render_layout(node, top)
  if node[1] == "leaf" then
    return node[2]
  end
  local separator = node[1] == "row" and " │ " or " ─ "
  local parts = vim.tbl_map(function(child)
    return M.render_layout(child, false)
  end, node[2])
  local text = table.concat(parts, separator)
  return top and text or ("(" .. text .. ")")
end

---@param goal vimdojo.Goal
---@return string[]
function M.describe(goal)
  return views[goal.type].describe(goal)
end

--- Rows the room needs beyond the level's start text.
---@param goal vimdojo.Goal
---@return integer
function M.extra_rows(goal)
  local extra_rows = views[goal.type].extra_rows
  return extra_rows and extra_rows(goal) or 0
end

---@param buf integer
---@param goal vimdojo.Goal
function M.decorate(buf, goal)
  vim.api.nvim_set_hl(0, "VimDojoTarget", { link = "IncSearch", default = true })
  vim.api.nvim_buf_clear_namespace(buf, M.namespace, 0, -1)
  views[goal.type].decorate(buf, goal)
end

return M
