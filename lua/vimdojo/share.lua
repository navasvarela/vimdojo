-- Spoiler-free result text a player can paste anywhere, Wordle-style. It
-- names the level and the score but never the keys. web/src/share.ts builds
-- the same text, and tests/fixtures/share.json pins both.
local ui = require("vimdojo.ui")

local M = {}

M.SITE_URL = "https://vimdojo.org"

---@class vimdojo.ShareView
---@field level_title string
---@field par_keys integer
---@field daily_date string|nil
---@field outcome vimdojo.Outcome

--- Rounds half up before formatting: `%.1f` rounds an exact tie such as 4.25
--- to even (4.2) while JavaScript's `toFixed` rounds it up (4.3), and the two
--- texts must match.
---@param seconds number
---@return string
local function tenths(seconds)
  return ("%.1f"):format(math.floor(seconds * 10 + 0.5) / 10)
end

---@param view vimdojo.ShareView
---@return string
function M.text(view)
  local name = view.daily_date and ("daily " .. view.daily_date) or ('"' .. view.level_title .. '"')
  local outcome = view.outcome
  local score = ("%s %d keys (par %d) %ss"):format(
    ui.stars(outcome.stars),
    outcome.keys,
    view.par_keys,
    tenths(outcome.seconds)
  )
  local hint = outcome.hinted and " · hint" or ""
  return ("vimdojo %s %s%s\n%s"):format(name, score, hint, M.SITE_URL)
end

return M
