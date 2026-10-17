-- Progress records and unlock rules. Pure data in, data out; persistence lives
-- in storage.lua.
local M = {}

M.VERSION = 1

---@class vimdojo.LevelRecord
---@field best_keys integer
---@field best_seconds number
---@field stars integer
---@field attempts integer

---@class vimdojo.Progress
---@field version integer
---@field levels table<string, vimdojo.LevelRecord>

---@class vimdojo.Result
---@field keys integer
---@field seconds number
---@field stars integer

---@return vimdojo.Progress
function M.empty()
  return { version = M.VERSION, levels = {} }
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

---@param progress vimdojo.Progress
---@param pack vimdojo.Pack
---@return boolean
function M.is_pack_completed(progress, pack)
  for _, level in ipairs(pack.levels) do
    if not M.is_completed(progress, level.id) then
      return false
    end
  end
  return true
end

--- A level unlocks when the previous level in its pack is completed; the first
--- level of a pack unlocks when every level of the previous pack is completed.
---@param progress vimdojo.Progress
---@param packs vimdojo.Pack[] Sorted by order.
---@return table<string, true> unlocked Set of unlocked level ids.
function M.unlocked_by_progress(progress, packs)
  local unlocked = {}
  local previous_pack_done = true
  for _, pack in ipairs(packs) do
    local previous_level_done = previous_pack_done
    for _, level in ipairs(pack.levels) do
      if previous_level_done then
        unlocked[level.id] = true
      end
      previous_level_done = previous_level_done and M.is_completed(progress, level.id)
    end
    previous_pack_done = previous_pack_done and M.is_pack_completed(progress, pack)
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
