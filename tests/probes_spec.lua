-- Every probe kind, run for real: a config is loaded in the sandbox and the
-- probe must pass against a config that does the job and fail against one
-- that doesn't.
local probes = require("vimdojo.probes")
local sandbox = require("vimdojo.sandbox")

-- Sandbox runs take ~50 ms; the margin is for slow CI runners.
local WAIT_MS = sandbox.TIMEOUT_MS + 2000

---@param config string[]
---@param list vimdojo.Probe[]
---@return vimdojo.SandboxReport
local function check(config, list)
  local report
  sandbox.run(config, list, function(result)
    report = result
  end)
  vim.wait(WAIT_MS, function()
    return report ~= nil
  end, 10)
  return assert(report, "the sandbox never reported")
end

local TRIM = {
  'vim.api.nvim_create_user_command("Trim", function()',
  [[  vim.cmd("%s/\\s\\+$//e")]],
  "end, {})",
}

local WRITE_ON_LEADER = {
  'vim.g.mapleader = " "',
  'vim.keymap.set("n", "<leader>w", "<cmd>write<CR>")',
}

local cases = {
  {
    kind = "option",
    probe = { kind = "option", name = "shiftwidth", value = 2 },
    pass = { "vim.opt.shiftwidth = 2" },
    fail = { "vim.bo.shiftwidth = 2" },
    message = "'shiftwidth' is 8, expected 2",
  },
  {
    kind = "keys",
    probe = {
      kind = "keys",
      keys = "ccnew<Esc><leader>w",
      lines = { "old" },
      expect = { lines = { "new" }, modified = false },
    },
    pass = WRITE_ON_LEADER,
    fail = { 'vim.g.mapleader = " "' },
    message = "modified is true, expected false",
  },
  {
    kind = "keys (search highlight)",
    probe = { kind = "keys", keys = "/x<CR><Esc>", lines = { "x" }, expect = { hlsearch = false } },
    pass = { 'vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR><Esc>")' },
    fail = { "vim.o.hlsearch = true" },
    message = "hlsearch is true, expected false",
  },
  {
    kind = "filetype",
    probe = { kind = "filetype", filetype = "markdown", expect = { textwidth = 80 } },
    pass = {
      'vim.api.nvim_create_autocmd("FileType", {',
      '  pattern = "markdown",',
      "  callback = function() vim.opt_local.textwidth = 80 end,",
      "})",
    },
    fail = { "vim.o.number = true" },
    message = "in a markdown buffer, textwidth is 0, expected 80",
  },
  {
    kind = "command",
    probe = { kind = "command", command = "Trim", lines = { "a  ", "b\t" }, expect = { "a", "b" } },
    pass = TRIM,
    fail = { "vim.o.number = true" },
    message = ":Trim failed: E492: Not an editor command: Trim",
  },
  {
    kind = "source_twice",
    probe = { kind = "source_twice", event = "BufWritePre" },
    pass = {
      'local group = vim.api.nvim_create_augroup("trim", { clear = true })',
      'vim.api.nvim_create_autocmd("BufWritePre", { group = group, command = "echo" })',
    },
    fail = { 'vim.api.nvim_create_autocmd("BufWritePre", { command = "echo" })' },
    message = "took BufWritePre autocommands from 1 to 2",
  },
  {
    kind = "extmarks_after",
    probe = { kind = "extmarks_after", keys = "yy", lines = { "yank me" } },
    pass = {
      'vim.api.nvim_create_autocmd("TextYankPost", {',
      "  callback = function() (vim.hl or vim.highlight).on_yank() end,",
      "})",
    },
    fail = { "vim.o.number = true" },
    message = "the buffer has 0 extmarks, expected at least 1",
  },
  {
    kind = "lua",
    probe = { kind = "lua", expr = "vim.g.mapleader == ' '", description = "the leader is Space" },
    pass = { 'vim.g.mapleader = " "' },
    fail = { 'vim.g.mapleader = ","' },
    message = "the leader is Space: got false",
  },
}

describe("probes in the sandbox", function()
  for _, case in ipairs(cases) do
    describe(case.kind, function()
      it("is a valid probe", function()
        assert.is_nil(probes.validate(case.probe))
      end)

      it("passes when the config does the job", function()
        local report = check(case.pass, { case.probe })
        assert.is_true(report.ok, vim.inspect(report))
      end)

      it("fails with a helpful message when it doesn't", function()
        local report = check(case.fail, { case.probe })
        assert.is_false(report.ok)
        local message = report.results[1].message or ""
        assert.is_truthy(message:find(case.message, 1, true), message)
      end)
    end)
  end
end)

describe("sandbox reports", function()
  local relativenumber = { kind = "option", name = "relativenumber", value = true }

  it("reports a load error with its line and still runs the probes", function()
    local report = check({ "vim.o.relativenumber = true", "local x = nil", "x.y = 1" }, {
      relativenumber,
    })
    assert.is_false(report.ok)
    assert.are.equal("init.lua:3: attempt to index local 'x' (a nil value)", report.load_error)
    assert.are.equal(3, report.error_line)
    assert.is_true(report.results[1].ok)
  end)

  it("points at the config line when the error is raised inside Neovim's runtime", function()
    local report = check({ "vim.o.number = true", 'vim.keymap.set("n", "x", nil)' }, {
      relativenumber,
    })
    assert.is_truthy(report.load_error:find("rhs", 1, true), report.load_error)
    assert.are.equal(2, report.error_line)
  end)

  it("reports a syntax error", function()
    local report = check({ "vim.o.number = = true" }, { relativenumber })
    assert.are.equal(1, report.error_line)
  end)

  it("stops a config that never finishes loading", function()
    local report = check({ "while true do end" }, { relativenumber })
    assert.is_false(report.ok)
    assert.is_truthy(report.load_error:find("took longer than", 1, true), report.load_error)
  end)

  it("reports a config that quits Neovim", function()
    local report = check({ "vim.cmd('qall!')" }, { relativenumber })
    assert.is_truthy(report.load_error:find("before the checks finished", 1, true))
  end)

  it("never sees the player's real config or data directories", function()
    local report = check({}, {
      {
        kind = "lua",
        description = "isolated",
        expr = ("vim.fn.stdpath('config') ~= %q and vim.fn.stdpath('data') ~= %q"):format(
          vim.fn.stdpath("config"),
          vim.fn.stdpath("data")
        ),
      },
    })
    assert.is_true(report.ok, vim.inspect(report))
  end)

  it("does not call back once cancelled", function()
    local called = false
    local run = sandbox.run({ "vim.o.number = true" }, { relativenumber }, function()
      called = true
    end)
    run.cancel()
    vim.wait(500, function()
      return called
    end, 10)
    assert.is_false(called)
  end)
end)

describe("probes.validate", function()
  local invalid = {
    { "not a table", "option", "probe must be an object" },
    { "unknown kind", { kind = "vibes" }, 'unknown probe kind "vibes"' },
    {
      "unknown option",
      { kind = "option", name = "relnum", value = true },
      'unknown option "relnum"',
    },
    { "table option value", { kind = "option", name = "list", value = {} }, "value must be" },
    { "keys without expect", { kind = "keys", keys = "x" }, "expect must be a non-empty object" },
    {
      "unknown keys expectation",
      { kind = "keys", keys = "x", expect = { mode = "n" } },
      'expect: unknown field "mode"',
    },
    {
      "bad cursor",
      { kind = "keys", keys = "x", cursor = { 0, 0 }, expect = { modified = true } },
      "cursor must be [line, col]",
    },
    {
      "filetype with an unknown option",
      { kind = "filetype", filetype = "go", expect = { tabwidth = 4 } },
      'expect: unknown option "tabwidth"',
    },
    { "command without lines", { kind = "command", command = "Trim", expect = { "x" } }, "lines" },
    {
      "unknown event",
      { kind = "source_twice", event = "BufSave" },
      'unknown autocommand event "BufSave"',
    },
    {
      "zero min",
      { kind = "extmarks_after", keys = "yy", min = 0 },
      "min must be an integer >= 1",
    },
    { "lua without description", { kind = "lua", expr = "true" }, "description must be" },
    {
      "lua that doesn't compile",
      { kind = "lua", expr = "((", description = "x" },
      "does not compile",
    },
    {
      "empty description",
      { kind = "option", name = "list", value = true, description = "" },
      "description",
    },
  }
  for _, case in ipairs(invalid) do
    local name, probe, expected = case[1], case[2], case[3]
    it("rejects " .. name, function()
      local err = probes.validate(probe) or ""
      assert.is_truthy(err:find(expected, 1, true), err)
    end)
  end

  it("rejects an empty probe list", function()
    assert.are.equal("probes must be a non-empty array", probes.validate_list({}))
  end)

  it("says which probe in a list is wrong", function()
    local err = probes.validate_list({
      { kind = "option", name = "list", value = true },
      { kind = "nope" },
    })
    assert.are.equal('probes[2]: unknown probe kind "nope"', err)
  end)
end)

describe("probes.describe", function()
  it("prefers the author's description", function()
    local probe = { kind = "option", name = "list", value = true, description = "Show tabs" }
    assert.are.equal("Show tabs", probes.describe(probe))
  end)

  it("falls back to a description of the kind", function()
    assert.are.equal(
      "'list' is true",
      probes.describe({ kind = "option", name = "list", value = true })
    )
    assert.are.equal(
      "go buffers get expandtab=false, shiftwidth=8",
      probes.describe({
        kind = "filetype",
        filetype = "go",
        expect = { shiftwidth = 8, expandtab = false },
      })
    )
  end)
end)

describe("probes.load.describe_error", function()
  local load = require("vimdojo.probes.load")

  it("takes the line from the message", function()
    assert.are.same(
      { message = "init.lua:4: boom", line = 4 },
      load.describe_error("init.lua:4: boom\nstack traceback:\n\tinit.lua:4: in main chunk")
    )
  end)

  it("takes the innermost config frame from the traceback", function()
    local err =
      "vim/keymap.lua:9: rhs: expected string\nstack traceback:\n\tvim/keymap.lua:9: in function 'set'\n\tinit.lua:7: in main chunk"
    assert.are.same(
      { message = "vim/keymap.lua:9: rhs: expected string", line = 7 },
      load.describe_error(err)
    )
  end)

  it("ignores runtime files whose name ends in init.lua", function()
    assert.are.same({ message = "vim/_init.lua:3: x" }, load.describe_error("vim/_init.lua:3: x"))
  end)
end)
