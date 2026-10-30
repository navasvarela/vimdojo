-- The daily challenge: one level per UTC day, the same in the plugin and on
-- the site (web/src/daily.ts implements the same picker, and
-- tests/fixtures/daily.json pins both). It needs no network: the date alone
-- picks the level.
local M = {}

local SECONDS_PER_DAY = 86400

-- Park-Miller "minimal standard" generator (MINSTD), chosen because its
-- products stay below 2^47, so Lua's doubles and JavaScript numbers compute
-- them exactly and the two clients agree. Changing either constant changes
-- every day's level in one client only.
local MODULUS = 2147483647
local MULTIPLIER = 48271

--- The levels the daily picks from: the browser demo's, so anyone can play
--- it on the site without installing anything. Sorted by id, so moving a
--- level between packs doesn't change the schedule; adding or removing one
--- does.
---@param packs vimdojo.Pack[]
---@return string[]
function M.pool(packs)
  local ids = {}
  for _, pack in ipairs(packs) do
    for _, level in ipairs(pack.levels) do
      if level.web_demo == true then
        table.insert(ids, level.id)
      end
    end
  end
  table.sort(ids)
  return ids
end

--- Days since 1970-01-01 UTC.
---@param epoch_seconds integer
---@return integer
function M.day_number(epoch_seconds)
  return math.floor(epoch_seconds / SECONDS_PER_DAY)
end

---@param day integer
---@return string date "YYYY-MM-DD", UTC.
function M.date(day)
  return tostring(os.date("!%Y-%m-%d", day * SECONDS_PER_DAY))
end

---@param pool string[]
---@param cycle integer
---@return string[]
local function shuffled(pool, cycle)
  local order = vim.list_extend({}, pool)
  local seed = (cycle % (MODULUS - 1)) + 1
  -- Fisher-Yates over 0-based positions, to mirror the TS port line by line.
  for i = #order - 1, 1, -1 do
    seed = (seed * MULTIPLIER) % MODULUS
    local j = seed % (i + 1)
    order[i + 1], order[j + 1] = order[j + 1], order[i + 1]
  end
  return order
end

--- Days are grouped into cycles as long as the pool. Each cycle plays every
--- level once, in an order shuffled from the cycle number, so a level never
--- comes back until the whole pool has been played.
---@param pool string[] Sorted level ids (see `M.pool`).
---@param day integer
---@return string|nil level_id Nil when the pool is empty.
function M.pick(pool, day)
  local size = #pool
  if size == 0 then
    return nil
  end
  local cycle = math.floor(day / size)
  local order = shuffled(pool, cycle)
  -- A cycle could start with the level the previous one ended on, which
  -- would repeat a daily two days running. Swapping the first two avoids it
  -- and leaves the last position alone, so the previous cycle's own swap
  -- never needs checking. With two levels it would, hence `size > 2`.
  if size > 2 and cycle > 0 and order[1] == shuffled(pool, cycle - 1)[size] then
    order[1], order[2] = order[2], order[1]
  end
  return order[(day % size) + 1]
end

return M
