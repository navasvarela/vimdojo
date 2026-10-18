-- `extmarks_after`: typing keys in a fixture file leaves extmarks behind,
-- e.g. the highlight vim.hl.on_yank() puts on yanked text.
local check = require("vimdojo.check")
local fields = require("vimdojo.probes.fields")
local fixture = require("vimdojo.probes.fixture")

--- Extmarks in `buf`, from one namespace or (when `namespace` is nil) all.
--- Counting every namespace by default keeps probes working when Neovim
--- renames one (the yank highlight moved from "hlyank" to "nvim.hlyank").
---@param buf integer
---@param namespace string|nil
---@return integer
local function count(buf, namespace)
  local total = 0
  for name, id in pairs(vim.api.nvim_get_namespaces()) do
    if namespace == nil or name == namespace then
      total = total + #vim.api.nvim_buf_get_extmarks(buf, id, 0, -1, {})
    end
  end
  return total
end

---@type vimdojo.ProbeKind
return {
  validate = function(probe)
    if probe.namespace ~= nil then
      local err = fields.string(probe, "namespace")
      if err then
        return err
      end
    end
    if probe.min ~= nil and not (check.is_integer(probe.min) and probe.min >= 1) then
      return "min must be an integer >= 1"
    end
    return fields.string(probe, "keys")
      or fields.optional_lines(probe, "lines")
      or fields.optional_cursor(probe)
  end,
  describe = function(probe)
    return ("pressing %s highlights the text"):format(probe.keys)
  end,
  run = function(probe)
    local buf = fixture.open(probe.lines, probe.cursor)
    local err = fixture.feed(probe.keys)
    local found, min = count(buf, probe.namespace), probe.min or 1
    if found < min then
      local message = ("after %s, the buffer has %d extmarks, expected at least %d"):format(
        probe.keys,
        found,
        min
      )
      return err and ("%s (error: %s)"):format(message, err) or message
    end
  end,
}
