-- `source_twice`: loading the config a second time (`:source $MYVIMRC`)
-- doesn't stack another copy of its autocommands for an event.
local fields = require("vimdojo.probes.fields")

---@param event string
---@return integer
local function count(event)
  return #vim.api.nvim_get_autocmds({ event = event })
end

---@type vimdojo.ProbeKind
return {
  validate = function(probe)
    local err = fields.string(probe, "event")
    if err then
      return err
    end
    if vim.fn.exists("##" .. probe.event) ~= 1 then
      return ("event: unknown autocommand event %q"):format(probe.event)
    end
  end,
  describe = function(probe)
    return ("sourcing the config twice doesn't duplicate %s autocommands"):format(probe.event)
  end,
  run = function(probe, context)
    local before = count(probe.event)
    local load_error = context.source_config()
    if load_error then
      return "sourcing the config again failed: " .. load_error.message
    end
    local after = count(probe.event)
    if after ~= before then
      return ("sourcing the config twice took %s autocommands from %d to %d; use an augroup with { clear = true }"):format(
        probe.event,
        before,
        after
      )
    end
  end,
}
