-- Turns boards and scores into the lines of a panel. Pure: data in, lines out.
local ui = require("vimdojo.ui")

local M = {}

local HANDLE_WIDTH = 22
local TITLE_WIDTH = 28
-- Marks a run that used the hint. It doesn't change the rank.
local HINTED_MARK = "*"

---@class vimdojo.BoardEntry
---@field rank integer
---@field handle string
---@field keys integer
---@field hinted boolean
---@field since string

---@class vimdojo.OwnRank
---@field rank integer|nil
---@field keys integer|nil

---@param rows vimdojo.MenuRows|table
---@param line string
---@param group string|nil
local function add(rows, line, group)
  table.insert(rows.lines, line)
  if group then
    table.insert(rows.highlights, { line = #rows.lines - 1, col = 0, group = group })
  end
end

---@param entries vimdojo.BoardEntry[]
---@param mine vimdojo.OwnRank|nil The player's place, when signed in.
---@return { lines: string[], highlights: vimdojo.Highlight[] }
function M.board_rows(entries, mine)
  local rows = { lines = { "" }, highlights = {} }
  if #entries == 0 then
    add(rows, "  No verified runs yet. Yours could be the first.", "VimDojoMuted")
  else
    add(
      rows,
      ("  %4s  %s  %5s  %s"):format("#", ui.pad("Player", HANDLE_WIDTH), "Keys", "Since"),
      "VimDojoMuted"
    )
  end
  local shown = false
  for _, entry in ipairs(entries) do
    local is_mine = mine ~= nil and mine.rank == entry.rank
    shown = shown or is_mine
    add(
      rows,
      ("  %4d  %s  %5s  %s"):format(
        entry.rank,
        ui.pad(entry.handle, HANDLE_WIDTH),
        tostring(entry.keys) .. (entry.hinted and HINTED_MARK or ""),
        entry.since
      ),
      is_mine and "VimDojoGood" or nil
    )
  end
  add(rows, "")
  if mine and mine.rank and not shown then
    add(rows, ("  You're #%d, with %d keys."):format(mine.rank, mine.keys), "VimDojoGood")
    add(rows, "")
  end
  if #entries > 0 then
    add(
      rows,
      ("  Verified keys. First to reach a count ranks ahead. %s used the hint."):format(HINTED_MARK),
      "VimDojoMuted"
    )
  end
  return rows
end

---@class vimdojo.Score
---@field level_id string
---@field keys integer
---@field rank integer
---@field hinted boolean

---@class vimdojo.ScoreLevel
---@field id string
---@field title string
---@field par_keys integer

--- Levels in curriculum order: verified ones with their place, then what's only on
--- this machine, so a player can see what they haven't sent.
---@param levels vimdojo.ScoreLevel[]
---@param scores vimdojo.Score[]
---@param local_keys table<string, integer> Level id -> keys of the local best run.
---@return { lines: string[], highlights: vimdojo.Highlight[], level_at: table<integer, string>, unsent: integer }
function M.score_rows(levels, scores, local_keys)
  local rows = { lines = { "" }, highlights = {}, level_at = {}, unsent = 0 }
  local by_level = {}
  for _, score in ipairs(scores) do
    by_level[score.level_id] = score
  end
  add(
    rows,
    ("  %s  %5s  %4s  %s"):format(ui.pad("Level", TITLE_WIDTH), "Keys", "Par", "Place"),
    "VimDojoMuted"
  )
  for _, level in ipairs(levels) do
    local score, keys = by_level[level.id], local_keys[level.id]
    local place = nil
    if score and keys and keys < score.keys then
      place = ("#%d (%d not sent)"):format(score.rank, keys)
      rows.unsent = rows.unsent + 1
    elseif score then
      place = ("#%d"):format(score.rank)
    elseif keys then
      place = "not sent"
      rows.unsent = rows.unsent + 1
    end
    if place then
      add(
        rows,
        ("  %s  %5s  %4d  %s"):format(
          ui.pad(level.title, TITLE_WIDTH),
          tostring(score and score.keys or keys) .. ((score and score.hinted) and HINTED_MARK or ""),
          level.par_keys,
          place
        )
      )
      rows.level_at[#rows.lines] = level.id
    end
  end
  if next(rows.level_at) == nil then
    add(rows, "  Nothing yet. Solve a level, then press s on its results card.", "VimDojoMuted")
  end
  add(rows, "")
  return rows
end

return M
