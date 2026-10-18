-- Runs inside the clean-room child for Setup levels: checks the init.lua the
-- player is editing in the sandbox (sandbox.lua) once the buffer settles in
-- Normal mode, and shows what failed as diagnostics in the buffer itself.
-- Diagnostics are drawn by the child, so showing them costs no keystrokes.
local sandbox = require("vimdojo.sandbox")

local M = {}

-- Long enough that a burst of Normal-mode edits (`dd`, `p`, `u`) runs one
-- check, short enough that the level completes right after the last edit.
M.DEBOUNCE_MS = 400

M.namespace = vim.api.nvim_create_namespace("vimdojo.config")

local uv = vim.uv or vim.loop

---@class vimdojo.ConfigCheck
---@field buf integer
---@field probes vimdojo.Probe[]
---@field on_result fun() Called after each verdict, to re-check the goal.
---@field timer uv.uv_timer_t
---@field running { tick: integer, run: vimdojo.SandboxRun }|nil
---@field verdict { tick: integer, report: vimdojo.SandboxReport }|nil
---@field stopped boolean
local ConfigCheck = {}
ConfigCheck.__index = ConfigCheck

---@param report vimdojo.SandboxReport
---@param line_count integer
---@return vim.Diagnostic[]
function M.diagnostics(report, line_count)
  local last = math.max(line_count - 1, 0)
  local items = {}
  if report.load_error then
    table.insert(items, {
      lnum = math.min(math.max((report.error_line or 1) - 1, 0), last),
      col = 0,
      severity = vim.diagnostic.severity.ERROR,
      message = report.load_error,
    })
  end
  local failures = vim.tbl_filter(function(result)
    return not result.ok
  end, report.results)
  if #failures > 0 then
    -- One line of virtual text fits one message; the header lists every check.
    local more = #failures > 1 and (" (+%d more)"):format(#failures - 1) or ""
    table.insert(items, {
      lnum = last,
      col = 0,
      severity = vim.diagnostic.severity.WARN,
      message = (failures[1].message or "a check failed") .. more,
    })
  end
  return items
end

---@param buf integer
---@param probes vimdojo.Probe[]
---@param on_result fun()
---@return vimdojo.ConfigCheck
function M.new(buf, probes, on_result)
  vim.diagnostic.config({
    virtual_text = true,
    signs = false,
    underline = false,
    update_in_insert = false,
    severity_sort = true,
  }, M.namespace)
  return setmetatable({
    buf = buf,
    probes = probes,
    on_result = on_result,
    timer = uv.new_timer(),
    stopped = false,
  }, ConfigCheck)
end

--- (Re)starts the debounce; the check runs once edits pause.
function ConfigCheck:schedule()
  if self.stopped then
    return
  end
  self.timer:stop()
  self.timer:start(
    M.DEBOUNCE_MS,
    0,
    vim.schedule_wrap(function()
      self:_run()
    end)
  )
end

---@return integer|nil
function ConfigCheck:_tick()
  if vim.api.nvim_buf_is_valid(self.buf) then
    return vim.api.nvim_buf_get_changedtick(self.buf)
  end
end

function ConfigCheck:_run()
  local tick = self:_tick()
  if self.stopped or not tick or vim.api.nvim_get_mode().mode ~= "n" then
    return
  end
  local current = (self.running and self.running.tick) or (self.verdict and self.verdict.tick)
  if tick == current then
    return
  end
  if self.running then
    self.running.run.cancel()
  end
  local lines = vim.api.nvim_buf_get_lines(self.buf, 0, -1, false)
  self.running = {
    tick = tick,
    run = sandbox.run(lines, self.probes, function(report)
      self:_finish(tick, report)
    end),
  }
end

---@param tick integer
---@param report vimdojo.SandboxReport
function ConfigCheck:_finish(tick, report)
  self.running = nil
  if self.stopped or not vim.api.nvim_buf_is_valid(self.buf) then
    return
  end
  self.verdict = { tick = tick, report = report }
  vim.diagnostic.set(
    M.namespace,
    self.buf,
    M.diagnostics(report, vim.api.nvim_buf_line_count(self.buf))
  )
  self.on_result()
end

--- The verdict for the buffer as it is now, or nil when the text changed
--- since the last check (or no check has finished yet).
---@return boolean|nil
function ConfigCheck:passed()
  if self.verdict and self.verdict.tick == self:_tick() then
    return self.verdict.report.ok == true
  end
end

--- Stops checking for good, e.g. when the level is solved or reset.
function ConfigCheck:stop()
  if self.stopped then
    return
  end
  self.stopped = true
  if self.running then
    self.running.run.cancel()
    self.running = nil
  end
  self.timer:stop()
  self.timer:close()
end

return M
