local helpers = require("helpers")
local share = require("vimdojo.share")

describe("share.text", function()
  for _, case in ipairs(helpers.fixture("share").cases) do
    it(case.name, function()
      assert.are.equal(case.expected, share.text(case.view))
    end)
  end
end)
