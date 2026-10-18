-- `command`: an Ex command (usually a user command the config defines) turns
-- the fixture lines into the expected lines.
local check = require("vimdojo.check")
local compare = require("vimdojo.probes.compare")
local fields = require("vimdojo.probes.fields")
local fixture = require("vimdojo.probes.fixture")

---@type vimdojo.ProbeKind
return {
  validate = function(probe)
    if not check.is_string_list(probe.lines) then
      return "lines must be a non-empty array of strings"
    end
    if not check.is_string_list(probe.expect) then
      return "expect must be a non-empty array of strings"
    end
    return fields.string(probe, "command")
  end,
  describe = function(probe)
    return (":%s fixes the sample text"):format(probe.command)
  end,
  run = function(probe)
    fixture.open(probe.lines)
    local ok, err = pcall(vim.cmd, probe.command)
    if not ok then
      return (":%s failed: %s"):format(probe.command, compare.error_message(err))
    end
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if not vim.deep_equal(lines, probe.expect) then
      return (":%s left %s, expected %s"):format(
        probe.command,
        compare.show(lines),
        compare.show(probe.expect)
      )
    end
  end,
}
