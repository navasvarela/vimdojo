local challenges = require("vimdojo.challenges")
local daily = require("vimdojo.daily")
local helpers = require("helpers")

describe("daily.pick", function()
  local fixture = helpers.fixture("daily")
  for _, case in ipairs(fixture.picks) do
    it(("picks %s on day %d (%s)"):format(case.level, case.day, case.date), function()
      assert.are.equal(case.level, daily.pick(fixture.pool, case.day))
      assert.are.equal(case.date, daily.date(case.day))
    end)
  end

  it("plays every level once per cycle", function()
    local size = #fixture.pool
    local cycle = {}
    for day = 3 * size, 4 * size - 1 do
      table.insert(cycle, daily.pick(fixture.pool, day))
    end
    table.sort(cycle)
    assert.are.same(fixture.pool, cycle)
  end)

  it("never repeats a level two days running", function()
    local previous
    for day = 0, 50 * #fixture.pool do
      local level = daily.pick(fixture.pool, day)
      assert.are_not.equal(previous, level)
      previous = level
    end
  end)

  it("has nothing to pick from an empty pool", function()
    assert.is_nil(daily.pick({}, 0))
  end)
end)

describe("daily.pool", function()
  it("is the demo levels, sorted by id", function()
    local packs = assert(challenges.load_dir())
    local pool = daily.pool(packs)
    assert.is_true(#pool > 0)
    local sorted = vim.list_extend({}, pool)
    table.sort(sorted)
    assert.are.same(sorted, pool)
    for _, id in ipairs(pool) do
      assert.is_true(challenges.find(packs, id).web_demo)
    end
  end)
end)

--- Packs shaped like the fixture's ramp: its legacy levels in a curriculum pack, its
--- tiers in a daily pack.
---@param ramp table
---@return vimdojo.Pack[]
local function ramp_packs(ramp)
  local legacy = vim.tbl_map(function(id)
    return { id = id, web_demo = true }
  end, ramp.legacy)
  local daily_levels = {}
  for difficulty, tier in ipairs(ramp.tiers) do
    for _, id in ipairs(tier) do
      table.insert(daily_levels, { id = id, web_demo = true, difficulty = difficulty })
    end
  end
  return {
    { pack = "curriculum", track = "motions", levels = legacy },
    { pack = "daily", track = "daily", daily_start = ramp.start, levels = daily_levels },
  }
end

describe("daily.level_for (weekly ramp)", function()
  local ramp = helpers.fixture("daily").ramp
  local schedule = daily.schedule(ramp_packs(ramp))

  for _, case in ipairs(ramp.picks) do
    it(("picks %s on %s"):format(case.level, case.date), function()
      assert.are.equal(case.level, daily.level_for(schedule, case.day))
      assert.are.equal(case.date, daily.date(case.day))
    end)
  end

  it("follows the weekday's tier from the start date", function()
    for day = schedule.start, schedule.start + 13 do
      local level = daily.level_for(schedule, day)
      local weekday_tier = ({ 1, 2, 3, 3, 4, 5, 5 })[(day - schedule.start) % 7 + 1]
      assert.is_true(vim.tbl_contains(ramp.tiers[weekday_tier], level))
    end
  end)

  it("lists the past dailies since the start, newest first", function()
    local listed = vim.tbl_map(function(past)
      return { date = past.date, level = past.level_id }
    end, daily.archive(schedule, ramp.archive.today))
    assert.are.same(ramp.archive.dates, listed)
  end)

  it("keeps the daily pack out of the old pool", function()
    assert.are.same(ramp.legacy, schedule.legacy)
  end)
end)

describe("daily.day_number", function()
  it("counts UTC days since the epoch", function()
    assert.are.equal(0, daily.day_number(86399))
    assert.are.equal(1, daily.day_number(86400))
  end)
end)
