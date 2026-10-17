local helpers = require("helpers")
local challenges = require("vimdojo.challenges")

---@return table
local function valid_level()
  return {
    id = "sample-01",
    title = "Sample",
    description = "A sample level.",
    start_text = { "hello world" },
    cursor_start = { 1, 0 },
    goal = { type = "cursor_at", line = 1, col = 6 },
    par_keys = 1,
    par_seconds = 5,
    hint = "w",
    solution = "w",
    teaches = { "w" },
  }
end

---@param overrides table|nil Fields to replace on the level.
---@return table
local function pack_with(overrides)
  local level = vim.tbl_extend("force", valid_level(), overrides or {})
  return { pack = "sample", title = "Sample", order = 1, levels = { level } }
end

---@param dir string
---@param name string
---@param pack table
local function write_pack(dir, name, pack)
  vim.fn.writefile({ vim.json.encode(pack) }, dir .. "/" .. name)
end

describe("challenges.validate_pack", function()
  it("accepts a valid pack", function()
    assert.are.same({}, challenges.validate_pack(pack_with()))
  end)

  local invalid = {
    { "missing title", { title = "" }, "title must be a non-empty string" },
    { "empty start_text", { start_text = {} }, "start_text must be a non-empty array" },
    { "zero par_keys", { par_keys = 0 }, "par_keys must be >= 1" },
    { "cursor line past the text", { cursor_start = { 2, 0 } }, "cursor_start line is outside" },
    { "cursor col past the line", { cursor_start = { 1, 11 } }, "cursor_start col is outside" },
    { "unknown goal type", { goal = { type = "mode_is" } }, 'goal: unknown goal type "mode_is"' },
    { "non-boolean web_demo", { web_demo = "yes" }, "web_demo must be a boolean" },
  }
  for _, case in ipairs(invalid) do
    local name, overrides, expected = case[1], case[2], case[3]
    it("rejects " .. name, function()
      local errors = challenges.validate_pack(pack_with(overrides))
      local all = table.concat(errors, "\n")
      assert.is_truthy(all:find(expected, 1, true), all)
    end)
  end

  it("accepts column 0 on an empty line", function()
    local errors =
      challenges.validate_pack(pack_with({ start_text = { "" }, cursor_start = { 1, 0 } }))
    assert.are.same({}, errors)
  end)
end)

describe("challenges.decode", function()
  it("reports invalid JSON", function()
    local pack, err = challenges.decode("{ nope")
    assert.is_nil(pack)
    assert.is_truthy(err:find("invalid JSON", 1, true))
  end)
end)

describe("challenges.load_dir", function()
  it("loads the shipped packs sorted by order", function()
    local packs = assert(challenges.load_dir())
    for i = 2, #packs do
      assert.is_true(packs[i - 1].order < packs[i].order)
    end
  end)

  it("ignores schema.json and sorts by order", function()
    local dir = helpers.temp_dir()
    local second = pack_with()
    second.pack, second.order = "second", 2
    second.levels[1].id = "second-01"
    write_pack(dir, "a.json", second)
    write_pack(dir, "b.json", pack_with())
    vim.fn.writefile({ "{}" }, dir .. "/schema.json")

    local packs = assert(challenges.load_dir(dir))
    assert.are.same({ "sample", "second" }, { packs[1].pack, packs[2].pack })
  end)

  it("rejects duplicate level ids across packs", function()
    local dir = helpers.temp_dir()
    local other = pack_with()
    other.pack, other.order = "other", 2
    write_pack(dir, "a.json", pack_with())
    write_pack(dir, "b.json", other)

    local packs, err = challenges.load_dir(dir)
    assert.is_nil(packs)
    assert.is_truthy(err:find('duplicate level id "sample-01"', 1, true))
  end)

  it("rejects an empty directory", function()
    local packs, err = challenges.load_dir(helpers.temp_dir())
    assert.is_nil(packs)
    assert.is_truthy(err:find("no challenge packs", 1, true))
  end)
end)
