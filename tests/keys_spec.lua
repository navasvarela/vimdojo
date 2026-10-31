local keys = require("vimdojo.keys")

describe("keys.split", function()
  local cases = {
    { "ffdw", { "f", "f", "d", "w" } },
    { "d2w", { "d", "2", "w" } },
    { "ciwfoo<Esc>", { "c", "i", "w", "f", "o", "o", "<Esc>" } },
    { "<C-r>a", { "<C-r>", "a" } },
    { "<C-^>", { "<C-^>" } },
    { "<C-]>x", { "<C-]>", "x" } },
    { "f<", { "f", "<" } },
    { "<lt>x", { "<lt>", "x" } },
    { "fé", { "f", "é" } },
    { "", {} },
  }
  for _, case in ipairs(cases) do
    local notation, expected = case[1], case[2]
    it(("splits %q"):format(notation), function()
      assert.are.same(expected, keys.split(notation))
    end)
  end

  it("counts keys", function()
    assert.are.equal(4, keys.count("cw<Esc>."))
  end)
end)

describe("keys.is_countable", function()
  local cases = {
    { "j", true },
    { "<", true },
    { "<Esc>", true },
    { "<C-r>", true },
    { "<LeftMouse>", false },
    { "<ScrollWheelDown>", false },
    { "<LeftDrag>", false },
    { "<LeftRelease>", false },
    { "<FocusGained>", false },
    { "<Ignore>", false },
  }
  for _, case in ipairs(cases) do
    local name, expected = case[1], case[2]
    it(("%s is %s"):format(name, expected and "counted" or "ignored"), function()
      assert.are.equal(expected, keys.is_countable(name))
    end)
  end
end)

describe("keys.name", function()
  local original = vim.fn.keytrans

  after_each(function()
    vim.fn.keytrans = original
  end)

  -- Nightly's keytrans() names these two; 0.12's returns them as they are.
  for _, spelling in ipairs({ "<Bar>", "|" }) do
    it(("spells %s as |"):format(spelling), function()
      vim.fn.keytrans = function()
        return spelling
      end
      assert.are.equal("|", keys.name("|"))
    end)
  end
  for _, spelling in ipairs({ "<Bslash>", "\\" }) do
    it(("spells %s as a backslash"):format(spelling), function()
      vim.fn.keytrans = function()
        return spelling
      end
      assert.are.equal("\\", keys.name("\\"))
    end)
  end
end)

describe("keys.paste_count", function()
  local cases = {
    { { "hello" }, 5 },
    { { "hello", "world" }, 11 },
    { { "", "" }, 1 },
    { { "é" }, 1 },
    { {}, 0 },
  }
  for _, case in ipairs(cases) do
    local lines, expected = case[1], case[2]
    it(("counts %s as %d keys"):format(vim.inspect(lines), expected), function()
      assert.are.equal(expected, keys.paste_count(lines))
    end)
  end
end)

describe("keys.capture", function()
  local stop

  after_each(function()
    if stop then
      stop()
      stop = nil
    end
  end)

  it("counts a paste as the keys it would take to type", function()
    local counted = 0
    stop = keys.capture(function()
      return true
    end, {
      on_keys = function() end,
      on_paste = function(count)
        counted = counted + count
      end,
    })
    vim.api.nvim_paste("ab\ncd", false, -1)
    assert.are.equal(5, counted)
  end)

  it("doesn't count a paste while inactive", function()
    local counted = 0
    stop = keys.capture(function()
      return false
    end, {
      on_keys = function() end,
      on_paste = function(count)
        counted = counted + count
      end,
    })
    vim.api.nvim_paste("ab", false, -1)
    assert.are.equal(0, counted)
  end)

  it("reports keys in the notation the verifier replays", function()
    local seen = {}
    stop = keys.capture(function()
      return true
    end, {
      on_keys = function(names)
        vim.list_extend(seen, names)
      end,
      on_paste = function() end,
    })
    vim.api.nvim_feedkeys(vim.keycode("i <|\\é<C-r><Esc><Esc>"), "tx", false)
    assert.are.same({ "i", "<Space>", "<lt>", "|", "\\", "é", "<C-R>", "<Esc>", "<Esc>" }, seen)
  end)

  it("restores vim.paste when stopped", function()
    local original = vim.paste
    keys.capture(function()
      return true
    end, { on_keys = function() end, on_paste = function() end })()
    assert.are.equal(original, vim.paste)
  end)
end)
