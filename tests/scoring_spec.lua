local helpers = require("helpers")
local scoring = require("vimdojo.scoring")

describe("scoring.score", function()
  for _, case in ipairs(helpers.fixture("scoring").cases) do
    it(case.name, function()
      assert.are.same(case.expected, scoring.score(case.attempt))
    end)
  end
end)
