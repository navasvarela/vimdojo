-- Runs every command from every screen in a real Neovim, and checks the player is never
-- left somewhere they can't see or can't leave. v0.7.0 shipped with `:VimDojo daily` over
-- the menu starting a hidden level that took every key, which tests of each screen on
-- its own can't find. A new screen or command belongs in these lists.
local player_mod = require("player")
local helpers = require("helpers")

local LEVEL = "basic-motions-01"
local SOLUTION = "jjjll"
-- More closes than any stack of screens needs, so a screen that won't close fails here
-- instead of looping forever.
local MAX_ESCAPE_STEPS = 6

-- The network is the one thing replaced: every other dependency is the real one.
local STUB_NETWORK = [[
  local level_id = ...
  local entry = { rank = 1, handle = "ana", keys = 4, hinted = false, since = "2026-10-31" }
  local online = require("vimdojo.online")
  online.save_token("vdj_test-token")
  online._set_deps({
    request = function(_, path, _, callback)
      if path == "/api/v1/daily" then
        callback({
          status = 200,
          body = { date = "2026-10-31", level_id = level_id, entries = { entry } },
        })
      elseif path == "/api/v1/me/scores" then
        callback({
          status = 200,
          body = { scores = { { level_id = level_id, keys = 5, rank = 3, hinted = false } } },
        })
      elseif path == "/api/v1/me" then
        callback({ status = 200, body = { handle = "ana" } })
      elseif path:match("/me$") then
        callback({ status = 404 })
      else
        callback({ status = 200, body = { entries = { entry } } })
      end
    end,
  })
]]

-- What must hold wherever the player ends up. Returns what's wrong, so a failure names it.
local PROBLEMS = [[
  local app = require("vimdojo.app")
  local play = app.current()
  local problems = {}
  if vim.v.errmsg ~= "" then
    table.insert(problems, "error: " .. vim.v.errmsg)
  end
  local panels, level_windows = 0, 0
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local zindex = vim.api.nvim_win_get_config(win).zindex
    if zindex == 60 then
      panels = panels + 1
    elseif zindex == 50 then
      level_windows = level_windows + 1
    end
  end
  local current = vim.api.nvim_get_current_win()
  if panels > 0 and vim.api.nvim_win_get_config(current).zindex ~= 60 then
    table.insert(problems, "a panel is showing, but the keys go somewhere behind it")
  end
  if not play and level_windows > 0 then
    table.insert(problems, "the level's windows outlived it")
  end
  if panels == 0 and play and play.ready and not play.session:is_finished() then
    if current ~= play.layout.room_win then
      table.insert(problems, "a level is showing, but it doesn't have the keys")
    elseif vim.api.nvim_get_mode().mode ~= "t" then
      table.insert(problems, "a level is showing, but not in Terminal mode")
    end
  end
  return problems
]]

local TOP_WINDOW = [[
  local play = require("vimdojo.app").current()
  local current = vim.api.nvim_get_current_win()
  local in_panel = vim.api.nvim_win_get_config(current).zindex == 60
  return {
    in_panel = in_panel,
    in_level = play ~= nil and not in_panel,
    windows = #vim.api.nvim_list_wins(),
  }
]]

---@param player Player
---@param command string
local function run(player, command)
  player:lua("vim.cmd(...)", "VimDojo " .. command)
end

---@param player Player
local function solve(player)
  assert.is_true(player:start(LEVEL))
  player:type(SOLUTION)
  assert.is_truthy(player:wait_for_record(LEVEL))
  assert.is_true(
    player:wait_for("require('vimdojo.app').current().session:is_finished()"),
    "the level never finished"
  )
end

---@type { name: string, open: fun(player: Player) }[]
local SCREENS = {
  { name = "nothing open", open = function() end },
  {
    name = "the menu",
    open = function(player)
      run(player, "menu")
    end,
  },
  {
    name = "help",
    open = function(player)
      run(player, "help")
    end,
  },
  {
    name = "help over the menu",
    open = function(player)
      run(player, "menu")
      run(player, "help")
    end,
  },
  {
    name = "a board",
    open = function(player)
      run(player, "board " .. LEVEL)
    end,
  },
  {
    name = "your scores",
    open = function(player)
      run(player, "scores")
    end,
  },
  {
    name = "a level",
    open = function(player)
      assert.is_true(player:start(LEVEL))
    end,
  },
  {
    name = "help over a level",
    open = function(player)
      assert.is_true(player:start(LEVEL))
      run(player, "help")
    end,
  },
  {
    name = "a board over a level",
    open = function(player)
      assert.is_true(player:start(LEVEL))
      run(player, "board " .. LEVEL)
    end,
  },
  { name = "the results card", open = solve },
  {
    name = "help over the results card",
    open = function(player)
      solve(player)
      run(player, "help")
    end,
  },
  {
    name = "a board over the results card",
    open = function(player)
      solve(player)
      run(player, "board " .. LEVEL)
    end,
  },
}

local COMMANDS = {
  "menu",
  "daily",
  "help",
  "reset",
  "hint",
  "quit",
  "board " .. LEVEL,
  "board daily",
  "scores",
  "account",
}

--- Leaves with the keys the screens advertise, as a player would.
---@param player Player
---@return boolean
local function escape(player)
  for _ = 1, MAX_ESCAPE_STEPS do
    local top = player:lua(TOP_WINDOW)
    if top.windows == 1 then
      return true
    end
    if top.in_panel then
      player:input("q")
    elseif top.in_level then
      player:type("<Esc><Esc>")
    else
      return false
    end
    vim.wait(100)
  end
  return player:lua(TOP_WINDOW).windows == 1
end

describe("every command from every screen", function()
  local player

  before_each(function()
    player = player_mod.spawn({
      online = {
        enabled = true,
        auth_path = helpers.temp_dir() .. "/auth.json",
        outbox_path = helpers.temp_dir() .. "/outbox.json",
      },
    })
    player:lua(STUB_NETWORK, LEVEL)
  end)

  after_each(function()
    player:stop()
  end)

  it("keeps the keys on the panel below when :q closes the one on top", function()
    run(player, "menu")
    run(player, "help")
    run(player, "board " .. LEVEL)
    player:lua("vim.cmd('quit')")
    assert.is_truthy(player:poll(function()
      return #player:lua(PROBLEMS) == 0 and player:lua(TOP_WINDOW).in_panel
    end))
    assert.is_true(escape(player), "the screens can't be closed with their own keys")
  end)

  for _, screen in ipairs(SCREENS) do
    for _, command in ipairs(COMMANDS) do
      it((":VimDojo %s from %s"):format(command, screen.name), function()
        screen.open(player)
        player:lua("vim.v.errmsg = ''")
        run(player, command)

        local problems
        player:poll(function()
          problems = player:lua(PROBLEMS)
          local play_ready = player:lua(
            "local play = require('vimdojo.app').current(); return not play or play.ready"
          )
          return play_ready and #problems == 0
        end)
        assert.are.same({}, problems)
        assert.is_true(escape(player), "the screens can't be closed with their own keys")
      end)
    end
  end
end)
