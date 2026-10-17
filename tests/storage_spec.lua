local helpers = require("helpers")
local progress = require("vimdojo.progress")
local storage = require("vimdojo.storage")

---@param path string
---@return string[]
local function siblings(path)
  return vim.fn.glob(vim.fn.fnamemodify(path, ":h") .. "/*", false, true)
end

describe("storage", function()
  local path

  before_each(function()
    path = helpers.temp_dir() .. "/nested/progress.json"
  end)

  it("returns empty progress when the file is missing", function()
    local data, warning = storage.load(path)
    assert.are.same(progress.empty(), data)
    assert.is_nil(warning)
  end)

  it("round-trips saved progress and creates parent directories", function()
    local data = progress.empty()
    progress.record(data, "basic-motions-01", { keys = 5, seconds = 7.4, stars = 3 })
    assert.is_true(storage.save(path, data))
    assert.are.same(data, (storage.load(path)))
  end)

  it("saves empty levels as a JSON object", function()
    assert.is_true(storage.save(path, progress.empty()))
    local text = table.concat(vim.fn.readfile(path), "\n")
    assert.is_truthy(text:find('"levels":{}', 1, true), text)
  end)

  it("leaves no temporary file behind", function()
    assert.is_true(storage.save(path, progress.empty()))
    assert.are.same({ path }, siblings(path))
  end)

  local corrupt = {
    { "invalid JSON", "{ not json" },
    { "wrong version", '{"version":99,"levels":{}}' },
    { "malformed record", '{"version":1,"levels":{"a":{"stars":"three"}}}' },
  }
  for _, case in ipairs(corrupt) do
    local name, content = case[1], case[2]
    it("backs up a file with " .. name .. " and starts fresh", function()
      vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
      vim.fn.writefile({ content }, path)

      local data, warning = storage.load(path)

      assert.are.same(progress.empty(), data)
      assert.is_truthy(warning)
      local files = siblings(path)
      assert.are.equal(1, #files)
      assert.is_truthy(files[1]:find("progress.json.corrupt-", 1, true))
      assert.are.same({ content }, vim.fn.readfile(files[1]))
    end)
  end
end)
