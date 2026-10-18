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
      "valid config_probes",
      { type = "config_probes", probes = { { kind = "option", name = "list", value = true } } },
      nil,
    },
    {
      "empty config_probes",
      { type = "config_probes", probes = {} },
      "probes must be a non-empty array",
    },
    {
      "invalid probe",
      { type = "config_probes", probes = { { kind = "nope" } } },
      'probes[1]: unknown probe kind "nope"',
    },
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

describe("config_probes", function()
  local goal = {
    type = "config_probes",
    probes = { { kind = "option", name = "list", value = true } },
  }

  it("is met only once the sandbox passed the current text", function()
    local state = { lines = { "x" }, cursor = { 1, 0 } }
    assert.is_false(goals.is_met(goal, state, { "x" }))
    state.config_passed = false
    assert.is_false(goals.is_met(goal, state, { "x" }))
    state.config_passed = true
    assert.is_true(goals.is_met(goal, state, { "x" }))
  end)

  it("lists its probes, including nested ones, in order", function()
    local other = { kind = "option", name = "number", value = true }
    local nested = {
      type = "all_of",
      goals = { goal, { type = "config_probes", probes = { other } } },
    }
    assert.are.same({ goal.probes[1], other }, goals.probes(nested))
    assert.are.same({}, goals.probes({ type = "cursor_at", line = 1, col = 0 }))
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

  it("lists every check of a config goal and leaves room to add lines", function()
    local goal = {
      type = "config_probes",
      probes = {
        { kind = "option", name = "list", value = true },
        {
          kind = "command",
          command = "Trim",
          lines = { "a " },
          expect = { "a" },
          description = "Trim it",
        },
      },
    }
    local lines = goal_views.describe(goal)
    assert.are.same(
      { "Goal: make this init.lua pass every check:", "  • 'list' is true", "  • Trim it" },
      vim.list_slice(lines, 1, 3)
    )
    assert.is_true(goal_views.extra_rows(goal) > 0)
    assert.are.equal(0, goal_views.extra_rows({ type = "buffer_equals", value = { "x" } }))
  end)
end)
