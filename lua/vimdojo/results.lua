-- The results card shown when an attempt reaches its goal.
local share = require("vimdojo.share")
local ui = require("vimdojo.ui")

local M = {}

---@class vimdojo.ResultsView
---@field level vimdojo.Level
---@field daily_date string|nil Set when this was the daily challenge.
---@field outcome vimdojo.Outcome
---@field record vimdojo.LevelRecord Best-so-far, including this attempt.
---@field has_next boolean
---@field can_submit boolean Offer to submit this run to the leaderboards.
---@field has_board boolean Offer to show this level's board.

---@class vimdojo.ResultsActions
---@field next fun()
---@field retry fun()
---@field menu fun()
---@field close fun()
---@field submit fun()
---@field board fun()

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
  local submit = (view.can_submit and "[s] submit   " or "")
    .. (view.has_board and "[b] board   " or "")
  local actions = view.has_next
      and ("  [n] next   [r] retry   [y] copy result   %s[m] menu   [q] quit"):format(submit)
    or ("  [r] retry   [y] copy result   %s[m] menu   [q] quit"):format(submit)
  table.insert(lines, actions)

  local highlights = {
    { line = 1, col = 2, end_col = 2 + #stars, group = "VimDojoStar" },
    { line = #lines - 1, col = 0, group = "VimDojoMuted" },
  }
  return lines, highlights
end

--- Puts the share text in the system clipboard when Neovim has one, and in
--- the unnamed register either way, so `p` pastes it inside Neovim.
---@param view vimdojo.ResultsView
local function copy_result(view)
  local text = share.text({
    level_title = view.level.title,
    par_keys = view.level.par_keys,
    daily_date = view.daily_date,
    outcome = view.outcome,
  })
  vim.fn.setreg('"', text)
  local where = "the unnamed register"
  if vim.fn.has("clipboard") == 1 and pcall(vim.fn.setreg, "+", text) then
    where = "the clipboard"
  end
  vim.notify(("vimdojo: result copied to %s"):format(where), vim.log.levels.INFO)
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
    y = function()
      copy_result(view)
    end,
    q = run(actions.close),
    ["<Esc>"] = run(actions.close),
  }
  if view.can_submit then
    -- Stays open: submitting is on the side of whatever the player does next.
    mappings.s = actions.submit
  end
  if view.has_board then
    mappings.b = actions.board
  end
  if view.has_next then
    mappings.n = run(actions.next)
    mappings["<CR>"] = run(actions.next)
  end
  ui.map(panel.buf, mappings)
  return panel
end

return M
