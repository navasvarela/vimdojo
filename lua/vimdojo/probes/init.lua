-- Behavior probes for Setup levels: declarative checks of what a player's
-- init.lua *does* (an option's value, what a mapping does to a buffer), not
-- how it's written, so `vim.keymap.set` and `vim.cmd("nnoremap ...")` both
-- pass. Validation runs in the game's Neovim when packs load; `run` runs
-- inside the sandbox (sandbox.lua) after the config has been loaded.
local check = require("vimdojo.check")

local M = {}

---@class vimdojo.Probe
---@field kind string
---@field description string|nil Shown in the level header; each kind has a default.

---@class vimdojo.ProbeContext
---@field source_config fun(): vimdojo.LoadError|nil Loads the player's config again.

---@class vimdojo.ProbeKind
---@field validate fun(probe: table): string|nil
---@field describe fun(probe: table): string
---@field run fun(probe: table, context: vimdojo.ProbeContext): string|nil Why the probe failed, or nil when it passed.

---@type table<string, vimdojo.ProbeKind>
local kinds = {
  option = require("vimdojo.probes.option"),
  keys = require("vimdojo.probes.keys"),
  filetype = require("vimdojo.probes.filetype"),
  command = require("vimdojo.probes.command"),
  source_twice = require("vimdojo.probes.source_twice"),
  extmarks_after = require("vimdojo.probes.extmarks_after"),
  lua = require("vimdojo.probes.lua"),
}

---@param probe any
---@return string|nil err
function M.validate(probe)
  if type(probe) ~= "table" then
    return "probe must be an object"
  end
  local kind = kinds[probe.kind]
  if not kind then
    return ("unknown probe kind %q"):format(tostring(probe.kind))
  end
  if probe.description ~= nil and not check.is_non_empty_string(probe.description) then
    return "description must be a non-empty string"
  end
  return (kind.validate(probe))
end

---@param probes any
---@return string|nil err
function M.validate_list(probes)
  if type(probes) ~= "table" or #probes == 0 then
    return "probes must be a non-empty array"
  end
  for index, probe in ipairs(probes) do
    local err = M.validate(probe)
    if err then
      return ("probes[%d]: %s"):format(index, err)
    end
  end
end

--- Callers must pass a probe that `validate` accepted.
---@param probe vimdojo.Probe
---@return string
function M.describe(probe)
  return probe.description or kinds[probe.kind].describe(probe)
end

--- Runs one probe in the sandbox. A probe that throws fails rather than
--- aborting the remaining probes.
---@param probe vimdojo.Probe
---@param context vimdojo.ProbeContext
---@return string|nil failure Why it failed, or nil when it passed.
function M.run(probe, context)
  local kind = kinds[probe.kind]
  if not kind then
    return ("unknown probe kind %q"):format(tostring(probe.kind))
  end
  local ok, failure = pcall(kind.run, probe, context)
  if not ok then
    return "the check crashed: " .. tostring(failure)
  end
  return failure
end

return M
