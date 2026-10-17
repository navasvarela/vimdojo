local compat = require("vimdojo.compat")

describe("compat", function()
  local current = { major = 0, minor = 11, patch = 2 }

  local cases = {
    { "no requirement", nil, true },
    { "older minor", "0.10", true },
    { "same minor", "0.11", true },
    { "same patch", "0.11.2", true },
    { "newer patch", "0.11.3", false },
    { "newer minor", "0.12", false },
    { "newer major", "1.0", false },
  }
  for _, case in ipairs(cases) do
    local name, required, expected = case[1], case[2], case[3]
    it(name, function()
      local level = { requires = required and { nvim = required } or nil }
      assert.are.equal(expected, compat.supports(level, current))
    end)
  end

  it("parses versions and rejects junk", function()
    assert.are.same({ major = 0, minor = 11, patch = 0 }, compat.parse("0.11"))
    assert.is_nil(compat.parse("0.11-dev"))
    assert.is_nil(compat.parse("eleven"))
  end)
end)
