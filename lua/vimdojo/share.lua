-- Spoiler-free result text a player can paste anywhere, Wordle-style. It
-- names the level and the score but never the keys. web/src/share.ts builds
-- the same text, and tests/fixtures/share.json pins both.
local daily = require("vimdojo.daily")
local ui = require("vimdojo.ui")

local M = {}

M.SITE_URL = "https://vimdojo.org"

---@class vimdojo.ShareView
---@field level_id string
---@field level_title string
---@field par_keys integer
---@field daily_date string|nil
---@field difficulty integer|nil Set for the daily pack's levels.
---@field outcome vimdojo.Outcome

--- Rounds half up before formatting: `%.1f` rounds an exact tie such as 4.25
--- to even (4.2) while JavaScript's `toFixed` rounds it up (4.3), and the two
--- texts must match.
---@param seconds number
---@return string
local function tenths(seconds)
  return ("%.1f"):format(math.floor(seconds * 10 + 0.5) / 10)
end

--- "daily 2026-11-17 (Tuesday, medium)": the day and how hard it is, so a shared
--- result says the dailies get harder through the week. Dailies from before the daily
--- pack have no difficulty, and keep the date alone.
---@param date string
---@param difficulty integer|nil
---@return string
local function daily_name(date, difficulty)
  local name = "daily " .. date
  if difficulty == nil then
    return name
  end
  return ("%s (%s, %s)"):format(name, daily.weekday_name(date), daily.DIFFICULTY_NAMES[difficulty])
end

---@param view vimdojo.ShareView
---@return string
function M.text(view)
  local name = view.daily_date and daily_name(view.daily_date, view.difficulty)
    or ('"' .. view.level_title .. '"')
  local outcome = view.outcome
  local score = ("%s %d keys (par %d) %ss"):format(
    ui.stars(outcome.stars),
    outcome.keys,
    view.par_keys,
    tenths(outcome.seconds)
  )
  local hint = outcome.hinted and " · hint" or ""
  -- The link names the level and the count, never the keys, so it stays spoiler-free. It
  -- goes to the level's share page, which previews as a card (web/build/share-pages.ts).
  local link = ("%s/play/%s/?beat=%d"):format(M.SITE_URL, view.level_id, outcome.keys)
  return ("vimdojo %s %s%s\nBeat it: %s"):format(name, score, hint, link)
end

return M
