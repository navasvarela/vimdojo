-- The results card shown when an attempt reaches its goal.
local ui = require("vimdojo.ui")

local M = {}

---@class vimdojo.ResultsView
---@field level vimdojo.Level
---@field outcome vimdojo.Outcome
---@field record vimdojo.LevelRecord Best-so-far, including this attempt.
---@field has_next boolean

---@class vimdojo.ResultsActions
---@field next fun()
---@field retry fun()
---@field menu fun()
---@field close fun()

---@param view vimdojo.ResultsView
---@return string[] lines
---@return vimdojo.Highlight[] highlights
function M.content(view)
  local outcome, level, record = view.outcome, view.level, view.record
  local stars = ui.stars(outcome.stars)
  local lines = {
    "",
    ("  %s   %d points"):format(stars, outcome.points),
    "",
    ("  Keys   %-8d par %d"):format(outcome.keys, level.par_keys),
    ("  Time   %-8s par %gs"):format(("%.1fs"):format(outcome.seconds), level.par_seconds),
    ("  Best   %d keys · %.1fs · %s"):format(
      record.best_keys,
      record.best_seconds,
      ui.stars(record.stars)
    ),
  }
  if outcome.hinted then
    table.insert(lines, "  Hint used: capped at 2 stars")
  end
  table.insert(lines, "")
  local actions = view.has_next and "  [n] next   [r] retry   [m] menu   [q] quit"
    or "  [r] retry   [m] menu   [q] quit"
  table.insert(lines, actions)

  local highlights = {
    { line = 1, col = 2, end_col = 2 + #stars, group = "VimDojoStar" },
    { line = #lines - 1, col = 0, group = "VimDojoMuted" },
  }
  return lines, highlights
end

---@param view vimdojo.ResultsView
---@param actions vimdojo.ResultsActions
---@return vimdojo.Panel
function M.open(view, actions)
  local lines, highlights = M.content(view)
  local panel = ui.open_panel({
    title = " " .. view.level.title .. ": solved ",
    lines = lines,
    highlights = highlights,
  })
  vim.wo[panel.win].cursorline = false

  local function run(action)
    return function()
      panel.close()
      action()
    end
  end
  local mappings = {
    r = run(actions.retry),
    m = run(actions.menu),
    q = run(actions.close),
    ["<Esc>"] = run(actions.close),
  }
  if view.has_next then
    mappings.n = run(actions.next)
    mappings["<CR>"] = run(actions.next)
  end
  ui.map(panel.buf, mappings)
  return panel
end

return M
