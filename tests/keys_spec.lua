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
