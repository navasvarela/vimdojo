local helpers = require("helpers")
local goals = require("vimdojo.goals")

describe("goals.is_met", function()
  for _, case in ipairs(helpers.fixture("goals").cases) do
    it(case.name, function()
      assert.are.equal(case.expected, goals.is_met(case.goal, case.state, case.start_lines))
    end)
  end
end)

describe("goals.validate", function()
  local cases = {
    { "valid buffer_equals", { type = "buffer_equals", value = { "a" } }, nil },
    { "valid cursor_at", { type = "cursor_at", line = 1, col = 0 }, nil },
    { "not a table", "cursor_at", "goal must be an object" },
    { "unknown type", { type = "mode_is" }, 'unknown goal type "mode_is"' },
    {
      "empty buffer_equals value",
      { type = "buffer_equals", value = {} },
      "value must be a non-empty array of strings",
    },
    {
      "zero line",
      { type = "cursor_at", line = 0, col = 0 },
      "line must be an integer >= 1",
    },
    {
      "fractional col",
      { type = "cursor_at", line = 1, col = 1.5 },
      "col must be an integer >= 0",
    },
    {
      "non-boolean allow_edit",
      { type = "cursor_at", line = 1, col = 0, allow_edit = "yes" },
      "allow_edit must be a boolean",
    },
  }
  for _, case in ipairs(cases) do
    local name, goal, expected = case[1], case[2], case[3]
    it(name, function()
      assert.are.equal(expected, goals.validate(goal))
    end)
  end
end)
