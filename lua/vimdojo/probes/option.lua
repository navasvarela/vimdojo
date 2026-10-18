-- `option`: an option has a value once the config is loaded, as seen from a
-- new buffer (so buffer-local values set only on the startup buffer don't
-- count).
local compare = require("vimdojo.probes.compare")
local check = require("vimdojo.check")

---@type vimdojo.ProbeKind
return {
  validate = function(probe)
    if not check.is_option_name(probe.name) then
      return ("name: unknown option %q"):format(tostring(probe.name))
    end
    local kind = type(probe.value)
    if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then
      return "value must be a string, number or boolean"
    end
  end,
  describe = function(probe)
    return ("'%s' is %s"):format(probe.name, compare.show(probe.value))
  end,
  run = function(probe)
    local actual = vim.api.nvim_get_option_value(probe.name, {})
    if actual ~= probe.value then
      return ("'%s' is %s, expected %s"):format(
        probe.name,
        compare.show(actual),
        compare.show(probe.value)
      )
    end
  end,
}
