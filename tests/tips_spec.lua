local helpers = require("helpers")
local tips = require("vimdojo.tips")

describe("tips", function()
  for _, case in ipairs(helpers.fixture("tips").cases) do
    it(case.name, function()
      local tip = tips.tip(case.keys)
      if case.tip then
        assert.are.equal(case.tip, tip)
      else
        assert.is_nil(tip)
      end
    end)
  end
end)
