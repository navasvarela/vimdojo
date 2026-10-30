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

describe("daily.day_number", function()
  it("counts UTC days since the epoch", function()
    assert.are.equal(0, daily.day_number(86399))
    assert.are.equal(1, daily.day_number(86400))
  end)
end)
