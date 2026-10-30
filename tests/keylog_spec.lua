local helpers = require("helpers")
local keylog = require("vimdojo.keylog")

---@param keys integer
---@param hash string|nil
---@return vimdojo.Run
local function run(keys, hash)
  return {
    version = keylog.VERSION,
    level_id = "level-01",
    level_hash = hash or "sha256:a",
    nvim = "0.12.6",
    keys = { "j" },
    deltas_ms = { 0 },
    claimed = { keys = keys, seconds = 1.5, hinted = false },
  }
end

describe("keylog.record", function()
  local dir

  before_each(function()
    dir = helpers.temp_dir()
  end)

  it("saves the first run", function()
    assert.is_true(keylog.record(dir, run(5)))
    assert.are.equal(5, keylog.load(dir, "level-01").claimed.keys)
  end)

  local cases = {
    { "keeps a better run", 5, "sha256:a", 4, "sha256:a", 4 },
    { "ignores a worse run", 5, "sha256:a", 6, "sha256:a", 5 },
    { "keeps the earlier run on a tie", 5, "sha256:a", 5, "sha256:a", 5, true },
    { "replaces a run on an older version of the level", 3, "sha256:a", 9, "sha256:b", 9 },
  }
  for _, case in ipairs(cases) do
    local name, first_keys, first_hash, next_keys, next_hash, expected, is_tie = unpack(case)
    it(name, function()
      local first = run(first_keys, first_hash)
      first.claimed.seconds = 1
      assert.is_true(keylog.record(dir, first))
      assert.is_true(keylog.record(dir, run(next_keys, next_hash)))
      local saved = keylog.load(dir, "level-01")
      assert.are.equal(expected, saved.claimed.keys)
      if is_tie then
        assert.are.equal(1, saved.claimed.seconds)
      end
    end)
  end

  it("replaces an unreadable file", function()
    vim.fn.writefile({ "not json" }, dir .. "/level-01.json")
    assert.is_nil(keylog.load(dir, "level-01"))
    assert.is_true(keylog.record(dir, run(7)))
    assert.are.equal(7, keylog.load(dir, "level-01").claimed.keys)
  end)

  it("ignores a saved run in a format it doesn't know", function()
    local future = run(1)
    future.version = keylog.VERSION + 1
    vim.fn.writefile({ vim.json.encode(future) }, dir .. "/level-01.json")
    assert.is_nil(keylog.load(dir, "level-01"))
  end)

  it("writes nothing for an id that isn't safe as a file name", function()
    local unsafe = run(1)
    unsafe.level_id = "../../escape"
    assert.is_true(keylog.record(dir, unsafe))
    assert.are.same({}, vim.fn.readdir(dir))
    assert.is_nil(keylog.load(dir, "../../escape"))
  end)
end)
