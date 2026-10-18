-- Runs inside the sandbox after the config has loaded (see run.lua): runs
-- every probe of the job and writes a JSON report for the game to read.
local load = require("vimdojo.probes.load")
local probes = require("vimdojo.probes")

local M = {}

---@class vimdojo.SandboxJob
---@field config string Path of the player's init.lua.
---@field probes vimdojo.Probe[]
---@field result string Where to write the report.

---@class vimdojo.ProbeResult
---@field ok boolean
---@field message string|nil Why it failed.

---@class vimdojo.SandboxReport
---@field ok boolean The config loaded without errors and every probe passed.
---@field load_error string|nil
---@field error_line integer|nil The config line the load error points at.
---@field results vimdojo.ProbeResult[] One per probe, in order.

-- Probes start from one window on an empty buffer, without search
-- highlighting, so one probe's leftovers can't decide the next.
local function fresh_editor()
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  vim.cmd("enew!")
  vim.cmd("nohlsearch")
end

---@param job vimdojo.SandboxJob
---@return vimdojo.SandboxReport
function M.run(job)
  local context = {
    source_config = function()
      return load.source(job.config)
    end,
  }
  local load_error = load.startup_error
  local report = {
    ok = load_error == nil,
    load_error = load_error and load_error.message,
    error_line = load_error and load_error.line,
    results = {},
  }
  for index, probe in ipairs(job.probes) do
    fresh_editor()
    local failure = probes.run(probe, context)
    report.results[index] = { ok = failure == nil, message = failure }
    report.ok = report.ok and failure == nil
  end
  return report
end

---@param job_path string
function M.main(job_path)
  local job_file = assert(io.open(job_path, "rb"))
  local job = vim.json.decode(job_file:read("*a"), { luanil = { object = true, array = true } })
  job_file:close()
  local report = M.run(job)
  local out = assert(io.open(job.result, "wb"))
  out:write(vim.json.encode(report))
  out:close()
end

return M
