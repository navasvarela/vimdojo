-- The pure parts of sandbox.lua and room/config_check.lua. Real sandbox runs
-- are in probes_spec.lua.
local config_check = require("vimdojo.room.config_check")
local sandbox = require("vimdojo.sandbox")

describe("sandbox", function()
  it("points every XDG directory into the run's own directory", function()
    local env = sandbox.environment("/tmp/run")
    assert.are.equal("vimdojo-sandbox", env.NVIM_APPNAME)
    for _, name in ipairs({
      "CONFIG_HOME",
      "DATA_HOME",
      "STATE_HOME",
      "CACHE_HOME",
      "CONFIG_DIRS",
      "DATA_DIRS",
    }) do
      assert.are.equal(1, env["XDG_" .. name]:find("/tmp/run/", 1, true), name)
    end
  end)

  it("starts a clean headless Neovim with the shim as its init", function()
    local cmd = sandbox.command("nvim", sandbox.paths("/tmp/run"))
    assert.are.same(
      { "nvim", "--headless", "--clean", "-n", "-i", "NONE", "-u", "/tmp/run/shim.lua", "-l" },
      vim.list_slice(cmd, 1, 9)
    )
    assert.is_truthy(cmd[10]:find("vimdojo/probes/run.lua", 1, true))
    assert.are.equal("/tmp/run/job.json", cmd[11])
  end)

  it("quotes paths in the shim so Windows backslashes survive", function()
    local shim = table.concat(sandbox.shim([[C:\lua]], [[C:\tmp\init.lua]]), "\n")
    assert.is_truthy(shim:find([["C:\\lua"]], 1, true), shim)
    assert.is_truthy(shim:find([["C:\\tmp\\init.lua"]], 1, true), shim)
    assert.is_not_nil(loadstring(shim))
  end)

  describe("report_from", function()
    it("decodes the report the runner wrote", function()
      local report =
        sandbox.report_from({ code = 0, timed_out = false }, '{"ok":true,"results":[{"ok":true}]}')
      assert.are.same({ ok = true, results = { { ok = true } } }, report)
    end)

    it("explains a timeout", function()
      local report = sandbox.report_from({ code = 0, timed_out = true }, nil)
      assert.is_false(report.ok)
      assert.is_truthy(report.load_error:find("took longer than 3 s", 1, true))
    end)

    it("explains a missing report", function()
      local report = sandbox.report_from({ code = 1, timed_out = false }, nil)
      assert.is_truthy(report.load_error:find("exited (code 1)", 1, true))
    end)

    it("rejects an unreadable report", function()
      local report = sandbox.report_from({ code = 0, timed_out = false }, "{")
      assert.are.same(
        { ok = false, load_error = "the checks wrote an unreadable report", results = {} },
        report
      )
    end)
  end)
end)

describe("config_check.diagnostics", function()
  local severity = vim.diagnostic.severity

  it("puts a load error on its line and the first failure on the last line", function()
    local items = config_check.diagnostics({
      ok = false,
      load_error = "init.lua:2: boom",
      error_line = 2,
      results = {
        { ok = true },
        { ok = false, message = "first" },
        { ok = false, message = "second" },
      },
    }, 3)
    assert.are.same({
      { lnum = 1, col = 0, severity = severity.ERROR, message = "init.lua:2: boom" },
      { lnum = 2, col = 0, severity = severity.WARN, message = "first (+1 more)" },
    }, items)
  end)

  it("keeps an error line past the end of the buffer inside it", function()
    local items =
      config_check.diagnostics({ ok = false, load_error = "x", error_line = 9, results = {} }, 2)
    assert.are.equal(1, items[1].lnum)
  end)

  it("is empty when everything passed", function()
    assert.are.same({}, config_check.diagnostics({ ok = true, results = { { ok = true } } }, 1))
  end)
end)
