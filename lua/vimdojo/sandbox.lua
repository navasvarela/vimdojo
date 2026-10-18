-- Runs a player's init.lua in a throwaway headless Neovim and checks it with
-- behavior probes (probes/). Setup levels use it from the clean room.
--
-- This is isolation, not a security sandbox: the code is the player's own,
-- running on their own machine with their own permissions. The point is that
-- it never touches their real config, plugins, data or session. Every XDG
-- directory and NVIM_APPNAME point into a temporary directory that is deleted
-- afterwards, and the process is killed after TIMEOUT_MS.
--
--   sandbox.run(lines, probes)
--     writes  <dir>/init.lua     the player's config
--             <dir>/shim.lua     -u: puts vimdojo on package.path, loads init.lua
--             <dir>/job.json     probes + where to write the report
--     runs    nvim --headless --clean -n -i NONE -u shim.lua -l probes/run.lua job.json
--     reads   <dir>/result.json  a vimdojo.SandboxReport
local M = {}

-- Generous for a config plus a handful of probes (a run takes ~50 ms on a
-- laptop), but short enough that an accidental infinite loop in the player's
-- config is reported quickly. Slow CI runners (Windows) stay well under it.
M.TIMEOUT_MS = 3000

M.APPNAME = "vimdojo-sandbox"

local uv = vim.uv or vim.loop

-- The directory holding the `vimdojo` modules (lua/ in a git checkout).
local LUA_DIR = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

---@class vimdojo.SandboxPaths
---@field dir string
---@field config string
---@field shim string
---@field job string
---@field result string

---@param dir string
---@return vimdojo.SandboxPaths
function M.paths(dir)
  return {
    dir = dir,
    config = dir .. "/init.lua",
    shim = dir .. "/shim.lua",
    job = dir .. "/job.json",
    result = dir .. "/result.json",
  }
end

--- The -u file. Paths are embedded with %q so Windows backslashes survive.
---@param lua_dir string
---@param config string
---@return string[] lines
function M.shim(lua_dir, config)
  return {
    ("local dir = %q"):format(lua_dir),
    "package.path = dir .. '/?.lua;' .. dir .. '/?/init.lua;' .. package.path",
    ("require('vimdojo.probes.load').startup(%q)"):format(config),
  }
end

---@param nvim string
---@param paths vimdojo.SandboxPaths
---@return string[]
function M.command(nvim, paths)
  return {
    nvim,
    "--headless",
    "--clean",
    "-n",
    "-i",
    "NONE",
    "-u",
    paths.shim,
    "-l",
    LUA_DIR .. "/vimdojo/probes/run.lua",
    paths.job,
  }
end

--- Every place Neovim reads or writes user state points into `dir`, so the
--- config can't see or change the player's real files.
---@param dir string
---@return table<string, string>
function M.environment(dir)
  local env = { NVIM_APPNAME = M.APPNAME }
  for _, name in ipairs({ "CONFIG_HOME", "DATA_HOME", "STATE_HOME", "CACHE_HOME" }) do
    env["XDG_" .. name] = dir .. "/xdg/" .. name:lower()
  end
  env.XDG_CONFIG_DIRS = dir .. "/xdg/config_dirs"
  env.XDG_DATA_DIRS = dir .. "/xdg/data_dirs"
  return env
end

---@param message string
---@return vimdojo.SandboxReport
local function failed(message)
  return { ok = false, load_error = message, results = {} }
end

---@class vimdojo.SandboxExit
---@field code integer
---@field timed_out boolean

--- Pure: the report for a finished sandbox process.
---@param exit vimdojo.SandboxExit
---@param result string|nil The report file's contents, if it was written.
---@return vimdojo.SandboxReport
function M.report_from(exit, result)
  if exit.timed_out then
    return failed(
      ("the config took longer than %g s to load and check (an endless loop?)"):format(
        M.TIMEOUT_MS / 1000
      )
    )
  end
  if not result then
    return failed(
      ("Neovim exited (code %d) before the checks finished; does the config quit?"):format(
        exit.code
      )
    )
  end
  local ok, report = pcall(vim.json.decode, result, { luanil = { object = true, array = true } })
  if not ok or type(report) ~= "table" or type(report.results) ~= "table" then
    return failed("the checks wrote an unreadable report")
  end
  return report
end

---@param path string
---@return string|nil
local function read(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  return text
end

---@param paths vimdojo.SandboxPaths
---@param lines string[]
---@param probes vimdojo.Probe[]
local function write_inputs(paths, lines, probes)
  vim.fn.mkdir(paths.dir, "p")
  vim.fn.writefile(lines, paths.config)
  vim.fn.writefile(M.shim(LUA_DIR, paths.config), paths.shim)
  vim.fn.writefile(
    { vim.json.encode({ config = paths.config, probes = probes, result = paths.result }) },
    paths.job
  )
end

---@class vimdojo.SandboxRun
---@field cancel fun() Kills the process; `on_done` is then never called.

--- Checks `lines` as an init.lua against `probes`, asynchronously.
---@param lines string[]
---@param probes vimdojo.Probe[]
---@param on_done fun(report: vimdojo.SandboxReport) Called on the main loop.
---@return vimdojo.SandboxRun
function M.run(lines, probes, on_done)
  local paths = M.paths(vim.fn.tempname())
  write_inputs(paths, lines, probes)
  local cancelled, timed_out = false, false
  local timer = uv.new_timer()

  local function finish(report)
    timer:stop()
    timer:close()
    vim.fn.delete(paths.dir, "rf")
    if not cancelled then
      on_done(report)
    end
  end

  local spawned, process = pcall(vim.system, M.command(vim.v.progpath, paths), {
    env = M.environment(paths.dir),
    cwd = paths.dir,
    stdin = false,
    -- Whatever the config prints is not part of the report.
    stdout = false,
    stderr = false,
  }, function(out)
    vim.schedule(function()
      finish(M.report_from({ code = out.code, timed_out = timed_out }, read(paths.result)))
    end)
  end)
  if not spawned then
    vim.schedule(function()
      finish(failed("could not start Neovim for the checks: " .. tostring(process)))
    end)
    return {
      cancel = function()
        cancelled = true
      end,
    }
  end

  -- SIGKILL, not vim.system's own timeout: Neovim handles SIGTERM on its
  -- event loop, which a config stuck in a Lua loop never returns to.
  local function kill()
    pcall(process.kill, process, "sigkill")
  end
  timer:start(M.TIMEOUT_MS, 0, function()
    timed_out = true
    kill()
  end)
  return {
    cancel = function()
      cancelled = true
      kill()
    end,
  }
end

return M
