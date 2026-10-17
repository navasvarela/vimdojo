-- Level select: packs with their levels, lock state, stars, and bests.
local ui = require("vimdojo.ui")

local M = {}

local TITLE_WIDTH = 28

---@class vimdojo.MenuModel
---@field packs vimdojo.Pack[]
---@field progress vimdojo.Progress
---@field unlocked table<string, true>

---@class vimdojo.MenuRows
---@field lines string[]
---@field highlights vimdojo.Highlight[]
---@field level_at table<integer, string> 1-based line number -> level id.
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

---@param model vimdojo.MenuModel
---@return vimdojo.MenuRows
function M.rows(model)
  local rows = { lines = { "" }, highlights = {}, level_at = {} }
  local function add(line, group)
    table.insert(rows.lines, line)
    if group then
      table.insert(rows.highlights, { line = #rows.lines - 1, col = 0, group = group })
    end
  end

  for _, pack in ipairs(model.packs) do
    add(("  %d. %s"):format(pack.order, pack.title), "VimDojoTitle")
    for index, level in ipairs(pack.levels) do
      local record = model.progress.levels[level.id]
      local name = ui.pad(("%02d %s"):format(index, level.title), TITLE_WIDTH)
      if model.unlocked[level.id] then
        local stars = record and ui.stars(record.stars) or ui.stars(0)
        add(("    %s  %s  %s"):format(stars, name, best_text(record)))
        table.insert(rows.highlights, {
          line = #rows.lines - 1,
          col = 4,
          end_col = 4 + #stars,
          group = "VimDojoStar",
        })
        if not record and not rows.first_open then
          rows.first_open = #rows.lines
        end
      else
        add(("    ···  %s  locked"):format(name), "VimDojoLocked")
      end
      rows.level_at[#rows.lines] = level.id
      rows.first_level = rows.first_level or #rows.lines
    end
    add("")
  end
  return rows
end

---@param model vimdojo.MenuModel
---@param on_select fun(level_id: string)
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
    local level_id = rows.level_at[line]
    if not level_id then
      return
    end
    if not model.unlocked[level_id] then
      vim.notify("vimdojo: finish the previous level to unlock this one", vim.log.levels.INFO)
      return
    end
    panel.close()
    on_select(level_id)
  end

  ui.map(panel.buf, { ["<CR>"] = select, q = panel.close, ["<Esc>"] = panel.close })
end

return M
