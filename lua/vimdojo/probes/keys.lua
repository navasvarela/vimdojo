-- `keys`: type keys in a fixture file, then check the buffer, cursor,
-- 'modified', v:hlsearch or the window count.
local check = require("vimdojo.check")
local compare = require("vimdojo.probes.compare")
local fields = require("vimdojo.probes.fields")
local fixture = require("vimdojo.probes.fixture")

local EXPECTABLE = {
  lines = check.is_string_list,
  cursor = check.is_position,
  modified = function(value)
    return type(value) == "boolean"
  end,
  hlsearch = function(value)
    return type(value) == "boolean"
  end,
  windows = function(value)
    return check.is_integer(value) and value >= 1
  end,
}

---@param expect any
---@return string|nil
local function expect_error(expect)
  if type(expect) ~= "table" or next(expect) == nil then
    return "expect must be a non-empty object"
  end
  for name, value in pairs(expect) do
    local valid = EXPECTABLE[name]
    if not valid then
      return ("expect: unknown field %q"):format(tostring(name))
    end
    if not valid(value) then
      return ("expect.%s has the wrong type"):format(name)
    end
  end
end

---@type vimdojo.ProbeKind
return {
  validate = function(probe)
    return fields.string(probe, "keys")
      or fields.optional_lines(probe, "lines")
      or fields.optional_cursor(probe)
      or expect_error(probe.expect)
  end,
  describe = function(probe)
    return ("pressing %s works"):format(probe.keys)
  end,
  run = function(probe)
    fixture.open(probe.lines, probe.cursor)
    local err = fixture.feed(probe.keys)
    local mismatch = compare.mismatch(probe.expect, fixture.state())
    if mismatch then
      local message = ("after %s, %s"):format(probe.keys, mismatch)
      return err and ("%s (error: %s)"):format(message, err) or message
    end
  end,
}
