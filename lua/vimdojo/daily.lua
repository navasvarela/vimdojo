-- The daily challenge: one level per UTC day, the same in the plugin and on
-- the site (web/src/daily.ts implements the same picker, and
-- tests/fixtures/daily.json pins both). It needs no network: the date alone
-- picks the level.
local challenges = require("vimdojo.challenges")

local M = {}

local SECONDS_PER_DAY = 86400

-- The weekly ramp: the tier (a daily level's difficulty) for each weekday, Monday
-- first. Easy at the start of the week, the nastiest edge cases at the weekend.
local TIER_OF_WEEKDAY = { 1, 2, 3, 3, 4, 5, 5 }
local DAYS_PER_WEEK = 7
-- 1970-01-01, day 0, was a Thursday: weekday 3 counting Monday as 0.
local EPOCH_WEEKDAY = 3

-- Park-Miller "minimal standard" generator (MINSTD), chosen because its
-- products stay below 2^47, so Lua's doubles and JavaScript numbers compute
-- them exactly and the two clients agree. Changing either constant changes
-- every day's level in one client only.
local MODULUS = 2147483647
local MULTIPLIER = 48271

--- The levels the daily picked from before the daily pack started: the browser
--- demo's, so anyone could play it on the site. Sorted by id, so moving a level
--- between packs doesn't change the schedule; adding or removing one does.
---@param packs vimdojo.Pack[]
---@return string[]
function M.pool(packs)
  local ids = {}
  for _, pack in ipairs(challenges.curriculum(packs)) do
    for _, level in ipairs(pack.levels) do
      if level.web_demo == true then
        table.insert(ids, level.id)
      end
    end
  end
  table.sort(ids)
  return ids
end

---@class vimdojo.DailySchedule
---@field legacy string[] The pool for days before `start` (see `M.pool`).
---@field start integer|nil The daily pack's first day; nil without a daily pack.
---@field tiers string[][] The daily pack's level ids by difficulty, each sorted.

---@param date string "YYYY-MM-DD"
---@return integer day Days since 1970-01-01.
local function day_of_date(date)
  local year, month, day = date:match("^(%d+)-(%d+)-(%d+)$")
  year, month, day = tonumber(year), tonumber(month), tonumber(day)
  -- Howard Hinnant's days_from_civil, so no time zone is involved:
  -- https://howardhinnant.github.io/date_algorithms.html#days_from_civil
  year = month <= 2 and year - 1 or year
  local era = math.floor(year / 400)
  local year_of_era = year - era * 400
  local day_of_year = math.floor((153 * (month + (month > 2 and -3 or 9)) + 2) / 5) + day - 1
  local day_of_era = year_of_era * 365
    + math.floor(year_of_era / 4)
    - math.floor(year_of_era / 100)
    + day_of_year
  return era * 146097 + day_of_era - 719468
end

---@param packs vimdojo.Pack[]
---@return vimdojo.DailySchedule
function M.schedule(packs)
  local schedule = { legacy = M.pool(packs), tiers = {} }
  for difficulty = 1, challenges.DIFFICULTY_MAX do
    schedule.tiers[difficulty] = {}
  end
  local pack = challenges.daily_pack(packs)
  if pack then
    schedule.start = day_of_date(pack.daily_start)
    for _, level in ipairs(pack.levels) do
      table.insert(schedule.tiers[level.difficulty], level.id)
    end
    for _, tier in ipairs(schedule.tiers) do
      table.sort(tier)
    end
  end
  return schedule
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

--- How many days before `day` had `tier`, counting from day 0.
---@param day integer
---@param tier integer
---@return integer
local function tier_days_before(day, tier)
  local weekday = (day + EPOCH_WEEKDAY) % DAYS_PER_WEEK
  local week = math.floor((day + EPOCH_WEEKDAY) / DAYS_PER_WEEK)
  local per_week, earlier_this_week = 0, 0
  for other, other_tier in ipairs(TIER_OF_WEEKDAY) do
    if other_tier == tier then
      per_week = per_week + 1
      if other - 1 < weekday then
        earlier_this_week = earlier_this_week + 1
      end
    end
  end
  return week * per_week + earlier_this_week
end

---@param day integer
---@return integer
local function tier_of(day)
  return TIER_OF_WEEKDAY[(day + EPOCH_WEEKDAY) % DAYS_PER_WEEK + 1]
end

--- The daily level on `day`: from the daily pack, by the weekly ramp, from its start
--- date, and from the old pool before it.
---@param schedule vimdojo.DailySchedule
---@param day integer
---@return string|nil level_id
function M.level_for(schedule, day)
  if schedule.start == nil or day < schedule.start then
    return M.pick(schedule.legacy, day)
  end
  -- Each tier plays like its own pool under `M.pick`, one "day" per time the tier
  -- comes up. Counting from the start date lines the tier's first cycle up with it,
  -- so no level comes back before the whole tier has been played.
  local tier = tier_of(day)
  local occurrence = tier_days_before(day, tier) - tier_days_before(schedule.start, tier)
  return M.pick(schedule.tiers[tier], occurrence)
end

---@class vimdojo.PastDaily
---@field date string
---@field level_id string

--- The daily pack's dailies before `today`, newest first. Days before the pack started
--- aren't included: their levels are in the curriculum anyway.
---@param schedule vimdojo.DailySchedule
---@param today integer
---@return vimdojo.PastDaily[]
function M.archive(schedule, today)
  local past = {}
  if schedule.start == nil then
    return past
  end
  for day = today - 1, schedule.start, -1 do
    local level_id = M.level_for(schedule, day)
    if level_id then
      table.insert(past, { date = M.date(day), level_id = level_id })
    end
  end
  return past
end

return M
