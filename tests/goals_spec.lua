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
    {
      "valid register_contains",
      { type = "register_contains", register = "a", value = { "x" } },
      nil,
    },
    {
      "uppercase register",
      { type = "register_contains", register = "A", value = { "x" } },
      'register must be one of a-z, 0-9, " or -',
    },
    {
      "valid all_of",
      { type = "all_of", goals = { { type = "cursor_at", line = 1, col = 0 } } },
      nil,
    },
    { "empty all_of", { type = "all_of", goals = {} }, "goals must be a non-empty array" },
    {
      "invalid goal inside all_of",
      { type = "all_of", goals = { { type = "cursor_at", line = 0, col = 0 } } },
      "goals[1]: line must be an integer >= 1",
    },
  }
  for _, case in ipairs(cases) do
    local name, goal, expected = case[1], case[2], case[3]
    it(name, function()
      assert.are.equal(expected, goals.validate(goal))
    end)
  end
end)

describe("goals.registers", function()
  it("lists the registers a goal reads, including nested ones", function()
    local goal = {
      type = "all_of",
      goals = {
        { type = "register_contains", register = "b", value = { "x" } },
        { type = "buffer_equals", value = { "x" } },
        {
          type = "all_of",
          goals = { { type = "register_contains", register = "a", value = { "y" } } },
        },
      },
    }
    assert.are.same({ "a", "b" }, goals.registers(goal))
  end)

  it("is empty for goals that read no registers", function()
    assert.are.same({}, goals.registers({ type = "cursor_at", line = 1, col = 0 }))
  end)
end)

describe("goal_views", function()
  local goal_views = require("vimdojo.goal_views")

  it("describes every goal kind, including nested ones", function()
    local lines = goal_views.describe({
      type = "all_of",
      goals = {
        { type = "register_contains", register = "a", value = { "keep me" }, linewise = true },
        { type = "buffer_equals", value = { "x" } },
      },
    })
    assert.are.same({
      'Goal: register "a" must hold (linewise):',
      "  │ keep me",
      "Goal: make the text read exactly:",
      "  │ x",
    }, lines)
  end)
end)
