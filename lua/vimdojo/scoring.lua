-- Score and star computation. Pure and dependency-free; web/src/scoring.ts is
-- a line-for-line port and both are tested against tests/fixtures/scoring.json.
--
-- Keystrokes weigh more than time because time alone rewards typing speed
-- rather than Vim skill.
local M = {}

M.MAX_POINTS = 1000
M.KEY_WEIGHT = 0.7
M.TIME_WEIGHT = 0.3
-- 2 stars allow up to 50% more keys than par: enough slack for a reasonable
-- but non-optimal solution, while still rewarding finding the short one.
M.TWO_STAR_KEY_FACTOR = 1.5
M.HINT_POINTS_FACTOR = 0.8
M.HINTED_MAX_STARS = 2

---@class vimdojo.Attempt
---@field keys integer
---@field seconds number
---@field par_keys integer
---@field par_seconds number
---@field hinted boolean

---@class vimdojo.Score
---@field stars integer 1 to 3.
---@field points integer 0 to MAX_POINTS.

--- 1 when at or under par, otherwise the fraction of par achieved.
---@param par number
---@param actual number
---@return number
local function par_ratio(par, actual)
  if actual <= par then
    return 1
  end
  return par / actual
end

---@param attempt vimdojo.Attempt
---@return integer
function M.stars(attempt)
  local stars = 1
  if attempt.keys <= attempt.par_keys and attempt.seconds <= attempt.par_seconds then
    stars = 3
  elseif attempt.keys <= attempt.par_keys * M.TWO_STAR_KEY_FACTOR then
    stars = 2
  end
  if attempt.hinted then
    return math.min(stars, M.HINTED_MAX_STARS)
  end
  return stars
end

---@param attempt vimdojo.Attempt
---@return integer
function M.points(attempt)
  local key_part = M.KEY_WEIGHT * par_ratio(attempt.par_keys, attempt.keys)
  local time_part = M.TIME_WEIGHT * par_ratio(attempt.par_seconds, attempt.seconds)
  local raw = M.MAX_POINTS * (key_part + time_part)
  if attempt.hinted then
    raw = raw * M.HINT_POINTS_FACTOR
  end
  return math.floor(raw + 0.5)
end

---@param attempt vimdojo.Attempt
---@return vimdojo.Score
function M.score(attempt)
  return { stars = M.stars(attempt), points = M.points(attempt) }
end

return M
