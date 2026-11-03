-- The browser names keys for web runs (web/src/key-notation.ts). Each name it can
-- produce must be what this plugin's key log would hold for the same key, or a web
-- run and a plugin run of the same keys would be cached and ranked as different.
local helpers = require("helpers")
local keys = require("vimdojo.keys")

describe("the browser's key names", function()
  for _, case in ipairs(helpers.fixture("key_notation").cases) do
    if case.notation then
      it(("%s is how a key log names it"):format(case.notation), function()
        assert.are.equal(case.notation, keys.name(vim.keycode(case.notation)))
      end)
    end
  end
end)
