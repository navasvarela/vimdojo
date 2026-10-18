-- `lua`: an escape hatch for checks no other probe expresses. The expression
-- must evaluate to true. Every use is reviewed in PRs; prefer a declarative
-- probe, and add a new kind when the same expression shows up twice.
local fields = require("vimdojo.probes.fields")
local compare = require("vimdojo.probes.compare")

---@param expr string
---@return function|nil chunk
---@return string|nil err
local function compile(expr)
  -- `vim.g.mapleader == " "` reads better in JSON than with a `return`.
  local chunk = loadstring("return " .. expr, "=probe")
  if chunk then
    return chunk
  end
  return loadstring(expr, "=probe")
end

---@type vimdojo.ProbeKind
return {
  validate = function(probe)
    local err = fields.string(probe, "expr") or fields.string(probe, "description")
    if err then
      return err
    end
    local _, compile_err = compile(probe.expr)
    if compile_err then
      return "expr does not compile: " .. compile_err
    end
  end,
  describe = function(probe)
    return probe.description
  end,
  run = function(probe)
    local chunk, compile_err = compile(probe.expr)
    if not chunk then
      return "the check does not compile: " .. tostring(compile_err)
    end
    local ok, result = pcall(chunk)
    if not ok then
      return "the check failed: " .. tostring(result)
    end
    if result ~= true then
      return ("%s: got %s"):format(probe.description, compare.show(result))
    end
  end,
}
