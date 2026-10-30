-- Level select: tracks, their packs and levels, with lock state, stars, and
-- bests.
local challenges = require("vimdojo.challenges")
local ui = require("vimdojo.ui")

local M = {}

local TITLE_WIDTH = 28

---@class vimdojo.MenuModel
---@field packs vimdojo.Pack[]
---@field progress vimdojo.Progress
---@field unlocked table<string, true>
---@field supports vimdojo.Supports Whether this Neovim can run a level.
---@field daily vimdojo.Daily|nil Today's daily challenge.

---@class vimdojo.MenuRows
---@field lines string[]
---@field highlights vimdojo.Highlight[]
---@field level_at table<integer, string> 1-based line number -> level id.
---@field daily_line integer|nil Line of the daily challenge.
---@field first_level integer|nil Line of the first level.
---@field first_open integer|nil Line of the first unlocked, unfinished level.

---@param record vimdojo.LevelRecord|nil
---@return string
local function best_text(record)
  if not record then
    return ""
  end
  return ("%d keys · %.1fs"):format(record.best_keys, record.best_seconds)
end

---@alias vimdojo.LevelAvailability "open"|"locked"|"unsupported"

---@param model vimdojo.MenuModel
---@param level vimdojo.Level
---@return vimdojo.LevelAvailability
function M.availability(model, level)
  if not model.supports(level) then
    return "unsupported"
  end
  return model.unlocked[level.id] and "open" or "locked"
end

---@param rows vimdojo.MenuRows
---@param line string
---@param group string|nil Highlight for the whole line.
local function add(rows, line, group)
  table.insert(rows.lines, line)
  if group then
    table.insert(rows.highlights, { line = #rows.lines - 1, col = 0, group = group })
  end
end

---@param rows vimdojo.MenuRows
---@param stars_count integer
---@param name string
---@param record vimdojo.LevelRecord|nil
local function add_open_level(rows, stars_count, name, record)
  local stars = ui.stars(stars_count)
  add(rows, ("    %s  %s  %s"):format(stars, name, best_text(record)))
  table.insert(rows.highlights, {
    line = #rows.lines - 1,
    col = 4,
    end_col = 4 + #stars,
    group = "VimDojoStar",
  })
end

--- The daily ignores locks, so it is always shown as open.
---@param rows vimdojo.MenuRows
---@param model vimdojo.MenuModel
local function add_daily(rows, model)
  local today = model.daily
  if not today then
    return
  end
  add(rows, ("  DAILY · %s"):format(today.date), "VimDojoMuted")
  local record = model.progress.levels[today.level.id]
  add_open_level(rows, record and record.stars or 0, ui.pad(today.level.title, TITLE_WIDTH), record)
  rows.daily_line = #rows.lines
  add(rows, "")
end

---@param rows vimdojo.MenuRows
---@param model vimdojo.MenuModel
---@param level vimdojo.Level
---@param index integer Position within its pack.
local function add_level(rows, model, level, index)
  local name = ui.pad(("%02d %s"):format(index, level.title), TITLE_WIDTH)
  local availability = M.availability(model, level)
  if availability == "unsupported" then
    add(
      rows,
      ("    ···  %s  needs Neovim %s"):format(name, level.requires.nvim),
      "VimDojoLocked"
    )
  elseif availability == "locked" then
    add(rows, ("    ···  %s  locked"):format(name), "VimDojoLocked")
  else
    local record = model.progress.levels[level.id]
    add_open_level(rows, record and record.stars or 0, name, record)
    if not record and not rows.first_open then
      rows.first_open = #rows.lines
    end
  end
  rows.level_at[#rows.lines] = level.id
  rows.first_level = rows.first_level or #rows.lines
end

---@param model vimdojo.MenuModel
---@return vimdojo.MenuRows
function M.rows(model)
  local rows = { lines = { "" }, highlights = {}, level_at = {} }
  add_daily(rows, model)
  for _, track in ipairs(challenges.TRACKS) do
    local packs = vim.tbl_filter(function(pack)
      return pack.track == track.id
    end, model.packs)
    if #packs > 0 then
      add(rows, ("  %s"):format(track.title:upper()), "VimDojoMuted")
      for _, pack in ipairs(packs) do
        add(rows, ("  %d. %s"):format(pack.order, pack.title), "VimDojoTitle")
        for index, level in ipairs(pack.levels) do
          add_level(rows, model, level, index)
        end
        add(rows, "")
      end
    end
  end
  return rows
end

---@class vimdojo.MenuActions
---@field level fun(level_id: string)
---@field daily fun()

---@param model vimdojo.MenuModel
---@param on_select vimdojo.MenuActions
function M.open(model, on_select)
  ui.define_highlights()
  local rows = M.rows(model)
  local panel = ui.open_panel({
    title = " vimdojo ",
    lines = rows.lines,
    highlights = rows.highlights,
    footer = " <CR> play · q close ",
  })
  local start_line = rows.first_open or rows.first_level or 1
  vim.api.nvim_win_set_cursor(panel.win, { start_line, 4 })

  local function select()
    local line = vim.api.nvim_win_get_cursor(panel.win)[1]
    if line == rows.daily_line then
      panel.close()
      on_select.daily()
      return
    end
    local level_id = rows.level_at[line]
    local level = level_id and challenges.find(model.packs, level_id)
    if not level then
      return
    end
    local availability = M.availability(model, level)
    if availability == "unsupported" then
      vim.notify(
        ("vimdojo: this level needs Neovim %s or newer"):format(level.requires.nvim),
        vim.log.levels.INFO
      )
    elseif availability == "locked" then
      vim.notify("vimdojo: finish the previous level to unlock this one", vim.log.levels.INFO)
    else
      panel.close()
      on_select.level(level_id)
    end
  end

  ui.map(panel.buf, { ["<CR>"] = select, q = panel.close, ["<Esc>"] = panel.close })
end

return M
