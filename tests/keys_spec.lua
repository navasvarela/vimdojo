local keys = require("vimdojo.keys")

describe("keys.split", function()
  local cases = {
    { "ffdw", { "f", "f", "d", "w" } },
    { "d2w", { "d", "2", "w" } },
    { "ciwfoo<Esc>", { "c", "i", "w", "f", "o", "o", "<Esc>" } },
    { "<C-r>a", { "<C-r>", "a" } },
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
