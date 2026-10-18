-- `filetype`: a new buffer of a filetype gets the expected options, e.g. from
-- a FileType autocommand.
local compare = require("vimdojo.probes.compare")
local fields = require("vimdojo.probes.fields")
local fixture = require("vimdojo.probes.fixture")

---@type vimdojo.ProbeKind
return {
  validate = function(probe)
    return fields.string(probe, "filetype") or fields.options(probe, "expect")
  end,
  describe = function(probe)
    return ("%s buffers get %s"):format(probe.filetype, fields.format_options(probe.expect))
  end,
  run = function(probe)
    vim.cmd("enew!")
    local ok, err = pcall(function()
      vim.bo.filetype = probe.filetype
    end)
    if not ok then
      return ("setting filetype %s failed: %s"):format(probe.filetype, compare.error_message(err))
    end
    local mismatch = compare.mismatch(probe.expect, fixture.options(vim.tbl_keys(probe.expect)))
    if mismatch then
      return ("in a %s buffer, %s"):format(probe.filetype, mismatch)
    end
  end,
}
