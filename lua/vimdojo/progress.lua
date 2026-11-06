-- Progress records and unlock rules. Pure data in, data out; persistence lives
-- in storage.lua.
local M = {}

M.VERSION = 1

---@class vimdojo.LevelRecord
---@field best_keys integer
---@field best_seconds number
---@field stars integer
---@field attempts integer

---@class vimdojo.DailyStreak
---@field streak integer Consecutive UTC days ending at `last_day`.
---@field best integer
---@field last_day integer Days since 1970-01-01 UTC.

---@class vimdojo.Progress
---@field version integer
---@field levels table<string, vimdojo.LevelRecord>
---@field daily vimdojo.DailyStreak|nil Absent until the first daily is solved.

---@class vimdojo.Result
---@field keys integer
---@field seconds number
---@field stars integer

---@return vimdojo.Progress
function M.empty()
  return { version = M.VERSION, levels = {} }
end

--- Counts today's daily once, however many times it's solved. A clock set back doesn't
--- rewrite the streak: the day is ignored, and the streak resumes when the date catches up.
--- web/src/progress.ts does the same, and tests/fixtures/streak.json pins both.
---@param progress vimdojo.Progress
---@param day integer
function M.record_daily(progress, day)
  local daily = progress.daily
  if daily and daily.last_day >= day then
    return
  end
  local streak = daily and daily.last_day == day - 1 and daily.streak + 1 or 1
  progress.daily = {
    streak = streak,
    best = math.max(daily and daily.best or 0, streak),
    last_day = day,
  }
end

--- The streak is still alive the day after the last solve, so a player sees what they
--- stand to lose instead of a zero before today's daily.
---@param progress vimdojo.Progress
---@param today integer
---@return integer
function M.current_streak(progress, today)
  local daily = progress.daily
  if not daily or daily.last_day < today - 1 then
    return 0
  end
  return daily.streak
end

--- Each best is tracked independently, so best_keys and best_seconds may come
--- from different attempts.
---@param previous vimdojo.LevelRecord|nil
---@param result vimdojo.Result
---@return vimdojo.LevelRecord
function M.merge(previous, result)
  if not previous then
    return {
      best_keys = result.keys,
      best_seconds = result.seconds,
      stars = result.stars,
      attempts = 1,
    }
  end
  return {
    best_keys = math.min(previous.best_keys, result.keys),
    best_seconds = math.min(previous.best_seconds, result.seconds),
    stars = math.max(previous.stars, result.stars),
    attempts = previous.attempts + 1,
  }
end

---@param progress vimdojo.Progress
---@param level_id string
---@param result vimdojo.Result
function M.record(progress, level_id, result)
  progress.levels[level_id] = M.merge(progress.levels[level_id], result)
end

---@param progress vimdojo.Progress
---@param level_id string
---@return boolean
function M.is_completed(progress, level_id)
  local record = progress.levels[level_id]
  return record ~= nil and record.stars >= 1
end

--- Whether any of the pack's levels is solved: until one is, the pack is new to the player.
---@param progress vimdojo.Progress
---@param pack vimdojo.Pack
---@return boolean
function M.has_solved_any(progress, pack)
  for _, level in ipairs(pack.levels) do
    if M.is_completed(progress, level.id) then
      return true
    end
  end
  return false
end

---@alias vimdojo.Supports fun(level: vimdojo.Level): boolean

---@type vimdojo.Supports
local function always()
  return true
end

--- A level that this Neovim cannot run (see compat.lua) never blocks the
--- levels after it.
---@param progress vimdojo.Progress
---@param level vimdojo.Level
---@param supports vimdojo.Supports
---@return boolean
local function is_cleared(progress, level, supports)
  return M.is_completed(progress, level.id) or not supports(level)
end

--- Unlock rules, per track (tracks progress independently):
---   - the first level of a track's first pack is always unlocked;
---   - a level unlocks when the previous level in its pack is cleared;
---   - a pack's first level unlocks when every level of the track's previous
---     pack is cleared.
--- "Cleared" means completed, or not runnable on this Neovim.
---@param progress vimdojo.Progress
---@param packs vimdojo.Pack[] Sorted by order.
---@param supports vimdojo.Supports|nil Defaults to every level being runnable.
---@return table<string, true> unlocked Set of unlocked level ids.
function M.unlocked_by_progress(progress, packs, supports)
  supports = supports or always
  local unlocked = {}
  ---@type table<string, boolean>
  local previous_pack_cleared = {}
  for _, pack in ipairs(packs) do
    local track = pack.track or "motions"
    local pack_open = previous_pack_cleared[track] ~= false
    local previous_cleared = pack_open
    for _, level in ipairs(pack.levels) do
      if previous_cleared then
        unlocked[level.id] = true
      end
      previous_cleared = previous_cleared and is_cleared(progress, level, supports)
    end
    previous_pack_cleared[track] = previous_cleared
  end
  return unlocked
end

---@param packs vimdojo.Pack[]
---@return table<string, true> unlocked Set of every level id.
function M.unlocked_all(packs)
  local unlocked = {}
  for _, pack in ipairs(packs) do
    for _, level in ipairs(pack.levels) do
      unlocked[level.id] = true
    end
  end
  return unlocked
end

return M
