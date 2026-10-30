-- End-to-end: a player's Neovim (tests/player.lua) plays levels in the clean
-- room, with keys fed through nvim_input() exactly as if typed.
local keylog = require("vimdojo.keylog")
local player_mod = require("player")

local CURRENT = "require('vimdojo.app').current()"
local CURRENT_LEVEL = "(require('vimdojo.app').current() or {}).level"

describe("playing a level", function()
  local player

  after_each(function()
    player:stop()
  end)

  describe("with default progression", function()
    before_each(function()
      player = player_mod.spawn()
    end)

    it("records keys, time, and stars when the goal is reached, and saves them", function()
      assert.is_true(player:start("basic-motions-01"))
      player:type("jjjll")

      local record = player:wait_for_record("basic-motions-01")
      assert.are.equal(5, record.best_keys)
      assert.are.equal(1, record.attempts)
      local saved = vim.json.decode(table.concat(vim.fn.readfile(player.progress_path), "\n"))
      assert.are.equal(5, saved.levels["basic-motions-01"].best_keys)
    end)

    it("keeps the run's keys privately, apart from the progress file", function()
      assert.is_true(player:start("basic-motions-01"))
      player:type("jjjll")
      player:wait_for_record("basic-motions-01")

      local run = keylog.load(player.keylog_dir, "basic-motions-01")
      assert.are.same({ "j", "j", "j", "l", "l" }, run.keys)
      assert.are.equal(5, #run.deltas_ms)
      assert.are.equal(5, run.claimed.keys)
      assert.is_truthy(run.level_hash:match("^sha256:%x+$"))
      local saved = table.concat(vim.fn.readfile(player.progress_path), "\n")
      assert.is_nil(saved:find("deltas_ms", 1, true))
    end)

    it("leaves game controls out of the key log", function()
      assert.is_true(player:start("basic-motions-01"))
      player:type("j\\h")
      assert.is_true(player:wait_for(CURRENT .. ".session.hinted"))
      player:type("jjll")
      player:wait_for_record("basic-motions-01")

      local run = keylog.load(player.keylog_dir, "basic-motions-01")
      assert.are.same({ "j", "j", "j", "l", "l" }, run.keys)
      assert.is_true(run.claimed.hinted)
    end)

    it("starts the key log over when the level is reset", function()
      assert.is_true(player:start("basic-motions-01"))
      player:type("kk\\r")
      assert.is_true(player:wait_for(CURRENT .. ".session.keys == 0"))
      player:type("jjjll")
      player:wait_for_record("basic-motions-01")

      assert.are.same(
        { "j", "j", "j", "l", "l" },
        keylog.load(player.keylog_dir, "basic-motions-01").keys
      )
    end)

    it("keeps no key log for a run with pasted text", function()
      assert.is_true(player:start("basic-motions-01"))
      assert.is_true(player:wait_for(CURRENT .. ".ready"))
      -- Bracketed paste inserts the text even in Normal mode, which typing the
      -- same keys wouldn't: that is why such a run can't be replayed.
      player:lua("vim.api.nvim_paste('x', false, -1)")
      assert.is_true(player:wait_for(CURRENT .. ".session.pasted"))
      player:type("ujjjll")

      assert.is_truthy(player:wait_for_record("basic-motions-01"))
      assert.is_nil(keylog.load(player.keylog_dir, "basic-motions-01"))
    end)

    it("does not count the hint key and marks the attempt as hinted", function()
      assert.is_true(player:start("basic-motions-01"))
      player:type("\\h")
      assert.is_true(player:wait_for(CURRENT .. ".session.hinted"))
      player:type("jjjll")

      local record = player:wait_for_record("basic-motions-01")
      assert.are.equal(5, record.best_keys)
      assert.are.equal(2, record.stars)
    end)

    it("resets the text, cursor, and counter in place", function()
      assert.is_true(player:start("basic-motions-01"))
      player:type("jjl")
      assert.is_true(player:wait_for(CURRENT .. ".room:snapshot().cursor[1] == 3"))
      assert.are.same({ 3, 1 }, player:snapshot().cursor)
      player:type("\\r")
      assert.is_true(player:wait_for(CURRENT .. ".room:snapshot().cursor[1] == 1"))
      assert.are.equal(0, player:lua("return " .. CURRENT .. ".session.keys"))
      player:type("jjjll")

      assert.are.equal(5, player:wait_for_record("basic-motions-01").best_keys)
    end)

    it("quits with <Esc><Esc> and restores the mouse option", function()
      local mouse = player:lua("return vim.o.mouse")
      assert.is_true(player:start("basic-motions-01"))
      assert.are.equal("", player:lua("return vim.o.mouse"))
      player:type("j<Esc><Esc>")

      assert.is_true(player:wait_for(CURRENT .. " == nil"))
      assert.are.equal(mouse, player:lua("return vim.o.mouse"))
      assert.is_nil(
        player:lua("return require('vimdojo.app').progress().levels['basic-motions-01']")
      )
    end)

    it("moves on to the next level from the results card", function()
      assert.is_true(player:start("basic-motions-01"))
      player:type("jjjll")
      player:wait_for_record("basic-motions-01")
      player:input("n")

      assert.are.equal("basic-motions-02", player:wait_for(CURRENT_LEVEL).id)
    end)

    it("closes the level when the room's Neovim exits", function()
      assert.is_true(player:start("basic-motions-01"))
      player:type(":qa!<CR>")

      assert.is_true(player:wait_for(CURRENT .. " == nil"))
    end)

    it("refuses to start a locked level", function()
      player:lua("require('vimdojo.app').start('basic-motions-02')")
      assert.is_nil(player:lua("return " .. CURRENT_LEVEL))
    end)

    it("opens the menu with :VimDojo", function()
      player:lua("vim.cmd('VimDojo')")
      local lines = player:lua("return vim.api.nvim_buf_get_lines(0, 0, -1, false)")
      assert.is_truthy(table.concat(lines, "\n"):find("Baby steps", 1, true))
    end)
  end)

  describe("with schema v2 packs", function()
    before_each(function()
      player =
        player_mod.spawn({ challenges_dir = require("helpers").root .. "/tests/fixtures/packs" })
    end)

    it("opens the first level of each track and gates unsupported levels", function()
      player:lua("vim.cmd('VimDojo')")
      local menu =
        table.concat(player:lua("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"), "\n")
      assert.is_truthy(menu:find("MOTIONS", 1, true))
      assert.is_truthy(menu:find("SETUP", 1, true))
      assert.is_truthy(menu:find("needs Neovim 99.0", 1, true))
      assert.is_true(player:start("v2-setup-first"))
    end)

    it("refuses to start a level this Neovim cannot run", function()
      player:lua(
        "require('vimdojo').setup({ unlock_all = true, challenges_dir = ... })",
        require("helpers").root .. "/tests/fixtures/packs"
      )
      player:lua("require('vimdojo.app').start('v2-future')")
      assert.is_nil(player:lua("return " .. CURRENT_LEVEL))
    end)

    it("starts a reset with the goal's registers cleared and presets reapplied", function()
      player:lua(
        "require('vimdojo').setup({ unlock_all = true, challenges_dir = ... })",
        require("helpers").root .. "/tests/fixtures/packs"
      )
      assert.is_true(player:start("v2-register-goal"))
      player:type('"ayy')
      assert.is_true(
        player:wait_for(CURRENT .. ".room:snapshot().registers.a.lines[1] == 'drop me'")
      )
      player:type("\\r")
      assert.is_true(player:wait_for(CURRENT .. ".room:snapshot().registers.a.lines[1] == nil"))
      player:type('j"ayy')

      assert.are.equal(5, player:wait_for_record("v2-register-goal").best_keys)
    end)
  end)

  describe("with every level unlocked", function()
    before_each(function()
      player = player_mod.spawn({ unlock_all = true })
    end)

    it("finishes an Insert-mode edit only after <Esc>, counting it", function()
      assert.is_true(player:start("operate-03"))
      player:type("fmcwnaps")
      assert.is_true(player:wait_for(CURRENT .. ".room:snapshot().lines[1] == 'I love naps'"))
      assert.is_false(player:lua("return " .. CURRENT .. ".session:is_finished()"))
      player:type("<Esc>")

      assert.are.equal(9, player:wait_for_record("operate-03").best_keys)
    end)

    it("keeps <Esc> working when the player maps it in Terminal mode", function()
      player:lua([[vim.keymap.set("t", "<Esc>", "<C-\\><C-n>")]])
      assert.is_true(player:start("operate-03"))
      player:type("fmcwnaps<Esc>")

      assert.are.equal(9, player:wait_for_record("operate-03").best_keys)
      player:input("q")
      assert.is_true(player:wait_for(CURRENT .. " == nil"))
      assert.are.equal([[<C-\><C-N>]], player:lua([[return vim.fn.maparg("<Esc>", "t")]]))
    end)
  end)
end)
