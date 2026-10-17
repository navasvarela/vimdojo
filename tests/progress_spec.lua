local progress = require("vimdojo.progress")

---@param id string
---@param level_ids string[]
---@return table
local function pack(id, level_ids)
  local levels = {}
  for _, level_id in ipairs(level_ids) do
    table.insert(levels, { id = level_id })
  end
  return { pack = id, levels = levels }
end

local PACKS = { pack("one", { "one-1", "one-2" }), pack("two", { "two-1", "two-2" }) }

---@param completed string[]
---@return vimdojo.Progress
local function progress_with(completed)
  local data = progress.empty()
  for _, id in ipairs(completed) do
    progress.record(data, id, { keys = 3, seconds = 2, stars = 1 })
  end
  return data
end

---@param set table<string, true>
---@return string[]
local function sorted_keys(set)
  local keys = vim.tbl_keys(set)
  table.sort(keys)
  return keys
end

describe("progress.merge", function()
  it("creates a record from the first attempt", function()
    local record = progress.merge(nil, { keys = 6, seconds = 4.5, stars = 2 })
    assert.are.same({ best_keys = 6, best_seconds = 4.5, stars = 2, attempts = 1 }, record)
  end)

  it("keeps each best independently and counts attempts", function()
    local previous = { best_keys = 6, best_seconds = 4.5, stars = 2, attempts = 1 }
    local record = progress.merge(previous, { keys = 5, seconds = 9, stars = 1 })
    assert.are.same({ best_keys = 5, best_seconds = 4.5, stars = 2, attempts = 2 }, record)
  end)
end)

describe("progress.unlocked_by_progress", function()
  local cases = {
    { "fresh progress unlocks only the first level", {}, { "one-1" } },
    { "completing a level unlocks the next", { "one-1" }, { "one-1", "one-2" } },
    {
      "completing a pack unlocks the next pack",
      { "one-1", "one-2" },
      { "one-1", "one-2", "two-1" },
    },
    {
      "levels in a locked pack stay locked even if recorded",
      { "two-1" },
      { "one-1" },
    },
  }
  for _, case in ipairs(cases) do
    local name, completed, expected = case[1], case[2], case[3]
    it(name, function()
      local unlocked = progress.unlocked_by_progress(progress_with(completed), PACKS)
      assert.are.same(expected, sorted_keys(unlocked))
    end)
  end
end)

describe("progress.unlocked_all", function()
  it("unlocks every level", function()
    assert.are.same(
      { "one-1", "one-2", "two-1", "two-2" },
      sorted_keys(progress.unlocked_all(PACKS))
    )
  end)
end)
