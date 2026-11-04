-- The results card shown when an attempt reaches its goal.
local help = require("vimdojo.help")
local share = require("vimdojo.share")
local ui = require("vimdojo.ui")

local M = {}

---@class vimdojo.StreakView
---@field current integer
---@field best integer

---@class vimdojo.ResultsView
---@field level vimdojo.Level
---@field daily_date string|nil Set when this was the daily challenge.
---@field outcome vimdojo.Outcome
---@field typed_keys string[]|nil What the player pressed. Nil when text was pasted.
---@field solution_hidden boolean It's today's daily: the board is still open.
---@field record vimdojo.LevelRecord Best-so-far, including this attempt.
---@field streak vimdojo.StreakView|nil Set when this solve was today's daily.
---@field tip string|nil A shorter way to type what the player typed (tips.lua).
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

-- Cut so that a long, wandering attempt doesn't stretch the card past the screen.
local MAX_TYPED_WIDTH = 60

--- Key notation spells a typed "<" as "<lt>" and a space as "<Space>", which read as
--- commands to a player. Key logs use both (keys.lua), so "You" lines need this too.
---@param keys string
---@return string
local function readable(keys)
  return (keys:gsub("<lt>", "<"):gsub("<Space>", " "))
end

---@param keys string[]
---@return string
local function typed_summary(keys)
  local shown = {}
  local width = 0
  for _, key in ipairs(keys) do
    width = width + #key
    if width > MAX_TYPED_WIDTH then
      table.insert(shown, "…")
      break
    end
    table.insert(shown, key)
  end
  return readable(table.concat(shown))
end

--- What the attempt can teach: the player's keys beside the par route. On today's
--- daily, showing it would let anyone copy their way up the board until the day ends.
-- The card's labels take 9 columns, and its other lines stay within 70.
local TIP_WIDTH = 61
local LABEL_INDENT = "         "

--- Wraps at spaces, so a tip doesn't widen the card past an 80-column screen.
---@param text string
---@param width integer|nil
---@return string[]
local function wrap(text, width)
  width = width or TIP_WIDTH
  local lines, line = {}, ""
  for word in text:gmatch("%S+") do
    if line ~= "" and vim.fn.strdisplaywidth(line .. " " .. word) > width then
      table.insert(lines, line)
      line = word
    else
      line = line == "" and word or line .. " " .. word
    end
  end
  table.insert(lines, line)
  return lines
end

-- Each step's text sits under its keys, indented past the label column.
local STEP_TEXT_INDENT = LABEL_INDENT .. "  "

--- The par route in steps, each with what it does (the level's `explain`).
---@param explain vimdojo.ExplainStep[]|nil
---@return string[]
local function step_lines(explain)
  if not explain then
    return {}
  end
  local lines = { "" }
  for index, step in ipairs(explain) do
    table.insert(lines, (index == 1 and "  Steps  " or LABEL_INDENT) .. readable(step.keys))
    for _, line in ipairs(wrap(step.text, TIP_WIDTH - 2)) do
      table.insert(lines, STEP_TEXT_INDENT .. line)
    end
  end
  return lines
end

---@param view vimdojo.ResultsView|vimdojo.PracticeView
---@return string[]
local function lesson_lines(view)
  local lines = {}
  if view.typed_keys then
    table.insert(lines, "  You    " .. typed_summary(view.typed_keys))
  end
  if view.tip then
    for index, line in ipairs(wrap(view.tip)) do
      table.insert(lines, (index == 1 and "  Tip    " or LABEL_INDENT) .. line)
    end
  end
  if view.solution_hidden then
    table.insert(lines, "  Par    shown once today's daily ends (00:00 UTC)")
    return lines
  end
  table.insert(lines, "  Par    " .. readable(view.level.solution))
  table.insert(lines, "  Learn  " .. table.concat(view.level.teaches, ", "))
  vim.list_extend(lines, step_lines(view.level.explain))
  return lines
end

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
  if view.streak then
    table.insert(
      lines,
      ("  Streak %d %s · best %d"):format(
        view.streak.current,
        view.streak.current == 1 and "day" or "days",
        view.streak.best
      )
    )
  end
  if outcome.hinted then
    table.insert(lines, "  Hint used: capped at 2 stars")
  end
  table.insert(lines, "")
  vim.list_extend(lines, lesson_lines(view))
  table.insert(lines, "")
  local board = view.daily_date and "[b] today's board   " or "[b] board   "
  local submit = (view.can_submit and "[s] submit   " or "") .. (view.has_board and board or "")
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
    level_id = view.level.id,
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

---@class vimdojo.PracticeView
---@field level vimdojo.Level
---@field outcome vimdojo.Outcome
---@field typed_keys string[]|nil
---@field solution_hidden boolean
---@field tip string|nil

---@class vimdojo.PracticeActions
---@field retry fun()
---@field menu fun()
---@field close fun()

---@param view vimdojo.PracticeView
---@return string[]
function M.practice_content(view)
  local lines = {
    "",
    ("  Solved in %d keys · par %d"):format(view.outcome.keys, view.level.par_keys),
    "  Practice: this attempt wasn't recorded",
    "",
  }
  vim.list_extend(lines, lesson_lines(view))
  vim.list_extend(lines, { "", "  [r] again   [m] menu   [q] quit" })
  return lines
end

---@param view vimdojo.PracticeView
---@param actions vimdojo.PracticeActions
---@return vimdojo.Panel
function M.open_practice(view, actions)
  local panel = ui.open_panel({
    title = " " .. view.level.title .. ": practice ",
    lines = M.practice_content(view),
    footer = " ? help ",
  })
  vim.wo[panel.win].cursorline = false
  local function run(action)
    return function()
      panel.close()
      action()
    end
  end
  ui.map(panel.buf, {
    r = run(actions.retry),
    ["<CR>"] = run(actions.retry),
    m = run(actions.menu),
    q = run(actions.close),
    ["<Esc>"] = run(actions.close),
    ["?"] = help.toggle,
  })
  return panel
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
    -- Not on the actions line, which is already wider than an 80-column screen
    -- with the leaderboard keys on it.
    footer = " ? help ",
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
    -- Stays open, for the player to come back to.
    ["?"] = help.toggle,
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
