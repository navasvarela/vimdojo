local challenges = require("vimdojo.challenges")
local helpers = require("helpers")
local level_hash = require("vimdojo.level_hash")

--- Fixtures are decoded the way packs are: vim.json keeps `{}` an empty object.
---@return table
local function fixture_cases()
  local path = helpers.root .. "/tests/fixtures/level_hash.json"
  local text = table.concat(vim.fn.readfile(path), "\n")
  return vim.json.decode(text, { luanil = { object = true, array = true } }).cases
end

describe("level_hash", function()
  for _, case in ipairs(fixture_cases()) do
    it(case.name, function()
      assert.are.equal(case.canonical, level_hash.canonical(case.level))
      assert.are.equal(case.hash, level_hash.of(case.level))
    end)
  end

  it("refuses a fractional number instead of hashing it differently from the web", function()
    local level = { start_text = { "a" }, cursor_start = { 1, 0.5 }, goal = {} }
    assert.has_error(function()
      level_hash.canonical(level)
    end)
  end)

  it("keeps an empty array an array", function()
    local level = { start_text = {}, cursor_start = { 1, 0 }, goal = { type = "x" } }
    assert.are.equal(
      '{"cursor_start":[1,0],"goal":{"type":"x"},"start_text":[]}',
      level_hash.canonical(level)
    )
  end)

  it("gives a workspace level the same hash once decoded from a pack", function()
    local case = fixture_cases()[5]
    local pack = assert(challenges.decode(vim.json.encode({
      pack = "p",
      title = "P",
      order = 1,
      levels = { case.level },
    })))
    assert.are.equal(case.hash, level_hash.of(pack.levels[1]))
  end)
end)

describe("verifier/manifest.json", function()
  local path = helpers.root .. "/verifier/manifest.json"
  local manifest = vim.json.decode(table.concat(vim.fn.readfile(path), "\n")).levels

  it("lists every shipped level with its current hash (run `make manifest`)", function()
    local expected = {}
    for _, pack in ipairs(assert(challenges.load_dir())) do
      for _, level in ipairs(pack.levels) do
        expected[level.id] = { hash = level_hash.of(level), ranked = pack.track ~= "setup" }
      end
    end
    assert.are.same(expected, manifest)
  end)
end)
