-- End-to-end: drives a real child Neovim through RPC. nvim_input() feeds keys
-- as if typed, so key capture, mappings, and autocmds behave as for a player.
local helpers = require("helpers")

local TIMEOUT_MS = 3000

---@class Child
---@field chan integer
---@field progress_path string
local Child = {}
Child.__index = Child

---@return Child
local function spawn()
  local chan = vim.fn.jobstart({
    vim.v.progpath,
    "--embed",
    "--headless",
    "--noplugin",
    "-u",
    helpers.root .. "/tests/minimal_init.lua",
  }, { rpc = true })
  local child =
    setmetatable({ chan = chan, progress_path = helpers.temp_dir() .. "/progress.json" }, Child)
  child:lua("require('vimdojo').setup({ progress_path = ... })", child.progress_path)
  return child
end

---@param code string Lua chunk; `...` holds the extra arguments.
---@return any value With RPC's vim.NIL mapped back to nil.
function Child:lua(code, ...)
  local value = vim.rpcrequest(self.chan, "nvim_exec_lua", code, { ... })
  if value == vim.NIL then
    return nil
  end
  return value
end

---@param keys string
function Child:input(keys)
  vim.rpcrequest(self.chan, "nvim_input", keys)
end

---@param code string Lua expression evaluated in the child.
---@return any
function Child:wait_for(code)
  local value
  vim.wait(TIMEOUT_MS, function()
    value = self:lua("return " .. code)
    return value ~= nil and value ~= false
  end, 20)
  return value
end

function Child:stop()
  vim.fn.jobstop(self.chan)
end

local RECORD = "require('vimdojo.app').progress().levels['basic-motions-01']"
local CURRENT_LEVEL = "(require('vimdojo.app').current() or {}).level"

describe("playing a level", function()
  local child

  before_each(function()
    child = spawn()
  end)

  after_each(function()
    child:stop()
  end)

  it("records keys, time, and stars when the goal is reached, and saves them", function()
    child:lua("require('vimdojo.app').start('basic-motions-01')")
    child:input("jjjll")

    local record = child:wait_for(RECORD)
    assert.are.equal(5, record.best_keys)
    assert.are.equal(1, record.attempts)
    local saved = vim.json.decode(table.concat(vim.fn.readfile(child.progress_path), "\n"))
    assert.are.equal(5, saved.levels["basic-motions-01"].best_keys)
  end)

  it("does not count the hint key and marks the attempt as hinted", function()
    child:lua("require('vimdojo.app').start('basic-motions-01')")
    child:input("\\h")
    assert.is_true(child:wait_for("require('vimdojo.app').current().session.hinted"))
    child:input("jjjll")

    local record = child:wait_for(RECORD)
    assert.are.equal(5, record.best_keys)
    assert.are.equal(2, record.stars)
  end)

  it("resets the text, cursor, and counter in place", function()
    child:lua("require('vimdojo.app').start('basic-motions-01')")
    child:input("jjl\\r")
    assert.are.same({ 1, 0 }, child:wait_for("vim.api.nvim_win_get_cursor(0)"))
    assert.are.equal(0, child:lua("return require('vimdojo.app').current().session.keys"))
    child:input("jjjll")

    assert.are.equal(5, child:wait_for(RECORD).best_keys)
  end)

  it("quits with <Esc><Esc> and restores the mouse option", function()
    local mouse = child:lua("return vim.o.mouse")
    child:lua("require('vimdojo.app').start('basic-motions-01')")
    assert.are.equal("", child:lua("return vim.o.mouse"))
    child:input("j<Esc><Esc>")

    assert.is_true(child:wait_for("require('vimdojo.app').current() == nil"))
    assert.are.equal(mouse, child:lua("return vim.o.mouse"))
    assert.is_nil(child:lua("return " .. RECORD))
  end)

  it("moves on to the next level from the results card", function()
    child:lua("require('vimdojo.app').start('basic-motions-01')")
    child:input("jjjll")
    child:wait_for(RECORD)
    child:input("n")

    local level = child:wait_for(CURRENT_LEVEL)
    assert.are.equal("basic-motions-02", level.id)
  end)

  it("refuses to start a locked level", function()
    child:lua("require('vimdojo.app').start('basic-motions-02')")
    assert.is_nil(child:lua("return " .. CURRENT_LEVEL))
  end)

  it("opens the menu with :VimDojo", function()
    child:lua("vim.cmd('VimDojo')")
    local lines = child:lua("return vim.api.nvim_buf_get_lines(0, 0, -1, false)")
    assert.is_truthy(table.concat(lines, "\n"):find("Baby steps", 1, true))
  end)
end)
