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

    describe("with a panel already open", function()
      local PANELS = [[
        local count = 0
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_config(win).zindex == 60 then
            count = count + 1
          end
        end
        return count
      ]]
      local IN_ROOM = "return " .. CURRENT .. ".layout.room_win == vim.api.nvim_get_current_win()"

      -- The menu has the higher zindex, so left open it hides the level, while focus
      -- and every key go to the level underneath.
      it("closes them when :VimDojo daily starts a level", function()
        player:lua("vim.cmd('VimDojo')")
        player:lua("vim.cmd('VimDojo help')")
        assert.are.equal(2, player:lua(PANELS))
        player:lua("vim.cmd('VimDojo daily')")
        assert.is_true(player:wait_for("(" .. CURRENT .. " or {}).ready"))
        assert.are.equal(0, player:lua(PANELS))
        assert.is_true(player:lua(IN_ROOM))
      end)

      it("doesn't stack a second menu on the first", function()
        player:lua("vim.cmd('VimDojo')")
        player:lua("vim.cmd('VimDojo')")
        assert.are.equal(1, player:lua(PANELS))
      end)

      it("still opens help after a level closed it", function()
        player:lua("vim.cmd('VimDojo help')")
        player:lua("vim.cmd('VimDojo daily')")
        assert.is_true(player:wait_for("(" .. CURRENT .. " or {}).ready"))
        player:lua("vim.cmd('VimDojo help')")
        assert.are.equal(1, player:lua(PANELS))
      end)
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
      assert.is_true(player:wait_for("(" .. CURRENT .. " or {}).ready"))
      -- Bracketed paste inserts the text even in Normal mode, which typing the
      -- same keys wouldn't: that is why such a run can't be replayed.
      player:lua("vim.api.nvim_paste('x', false, -1)")
      assert.is_true(player:wait_for(CURRENT .. ".session.pasted"))
      -- The room handles a paste asynchronously, so `u` must wait for the text.
      assert.is_truthy(player:wait_for(CURRENT .. ".room:snapshot().lines[1]:find('x', 1, true)"))
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

    it("shows the player's keys beside the par route", function()
      assert.is_true(player:start("basic-motions-01"))
      player:type("jjjlhll")
      player:wait_for_record("basic-motions-01")

      local card =
        table.concat(player:lua("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"), "\n")
      assert.is_truthy(card:find("You    jjjlhll", 1, true))
      assert.is_truthy(card:find("Par    jjjll", 1, true))
      assert.is_truthy(card:find("Learn  j, l", 1, true))
    end)

    it("gives a tip on a solve over par, and none at par", function()
      local TEXT = "return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n')"
      assert.is_true(player:start("basic-motions-01"))
      -- Down, back up, then down the rest of the way in a run a count would shorten.
      player:type("jkjjjll")
      assert.is_truthy(player:wait_for_record("basic-motions-01"))
      assert.is_truthy(player:poll(function()
        return player:lua(TEXT):find("`3j` does the same", 1, true)
      end))

      player:input("r")
      assert.is_truthy(player:wait_for("(" .. CURRENT .. " or {}).ready == true"))
      player:type("jjjll")
      assert.is_truthy(player:wait_for(CURRENT .. ".session:is_finished()"))
      assert.is_nil(player:lua(TEXT):find("Tip", 1, true))
    end)

    describe("daily streaks", function()
      local FIX_CLOCK_ON_DAILY = [[
        local daily = require("vimdojo.daily")
        local challenges = require("vimdojo.challenges")
        local pool = daily.pool(challenges.load_dir(challenges.default_dir()))
        local day = 0
        while daily.pick(pool, day) ~= "basic-motions-01" do
          day = day + 1
        end
        os.time = function()
          return day * 86400
        end
      ]]
      local TEXT = "return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n')"
      local FINISHED = CURRENT .. ".session:is_finished()"

      before_each(function()
        player:lua(FIX_CLOCK_ON_DAILY)
      end)

      it("starts on today's daily, shows on the card and menu, and is saved", function()
        player:lua("require('vimdojo.app').start_daily()")
        assert.is_truthy(player:wait_for("(" .. CURRENT .. " or {}).ready"))
        player:type("jjjll")
        assert.is_true(player:wait_for(FINISHED))
        assert.is_truthy(player:lua(TEXT):find("Streak 1 day · best 1", 1, true))
        local saved = vim.json.decode(table.concat(vim.fn.readfile(player.progress_path), "\n"))
        assert.are.equal(1, saved.daily.streak)

        player:input("m")
        assert.is_truthy(player:wait_for("not " .. CURRENT))
        assert.is_truthy(player:poll(function()
          return player:lua(TEXT):find("1-day streak (best 1)", 1, true)
        end))
      end)

      it("doesn't start on any other level", function()
        -- The next day's daily is a different level: a level never repeats two days running.
        player:lua("local today = os.time(); os.time = function() return today + 86400 end")
        assert.is_true(player:start("basic-motions-01"))
        player:type("jjjll")
        assert.is_truthy(player:wait_for_record("basic-motions-01"))
        assert.is_nil(player:lua("return require('vimdojo.app').progress().daily"))
      end)

      it("isn't extended by practising the daily", function()
        player:lua("vim.cmd('VimDojo practice basic-motions-01')")
        assert.is_truthy(player:wait_for("(" .. CURRENT .. " or {}).ready"))
        player:type("jjjll")
        assert.is_true(player:wait_for(FINISHED))
        assert.is_nil(player:lua("return require('vimdojo.app').progress().daily"))
      end)
    end)

    describe("practice", function()
      local FINISHED = CURRENT .. ".session:is_finished()"
      local TEXT = "return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n')"

      local function solve_in_practice()
        player:lua("vim.cmd('VimDojo practice basic-motions-01')")
        assert.is_truthy(player:wait_for("(" .. CURRENT .. " or {}).ready"))
        player:type("jjjll")
        assert.is_true(player:wait_for(FINISHED))
      end

      it("records nothing: no progress, file or key log", function()
        solve_in_practice()
        assert.are.same(
          {},
          player:lua("return vim.tbl_keys(require('vimdojo.app').progress().levels)")
        )
        assert.are.equal(0, vim.fn.filereadable(player.progress_path))
        assert.are.same({}, vim.fn.readdir(player.keylog_dir))
        local text = player:lua(TEXT)
        assert.is_truthy(text:find("Solved in 5 keys · par 5", 1, true))
        assert.is_truthy(text:find("wasn't recorded", 1, true))
      end)

      it("goes again with r, still as practice", function()
        solve_in_practice()
        player:input("r")
        assert.is_truthy(
          player:wait_for("(" .. CURRENT .. " or {}).ready == true and not " .. FINISHED)
        )
        assert.is_true(player:lua("return " .. CURRENT .. ".practice"))
      end)

      it("opens from the menu with p", function()
        player:lua("vim.cmd('VimDojo')")
        player:input("p")
        assert.is_truthy(player:wait_for("(" .. CURRENT .. " or {}).practice"))
      end)

      it("won't open a locked level", function()
        player:lua("vim.cmd('VimDojo practice regex-01')")
        assert.is_nil(player:lua("return " .. CURRENT))
      end)

      it("says how to use it without a level", function()
        player:lua("vim.cmd('VimDojo practice')")
        assert.is_nil(player:lua("return " .. CURRENT))
      end)
    end)

    it("keeps the par route back on today's daily", function()
      -- Fixes the clock on a day whose daily is a level with a known solution.
      player:lua([[
        local daily = require("vimdojo.daily")
        local challenges = require("vimdojo.challenges")
        local pool = daily.pool(challenges.load_dir(challenges.default_dir()))
        local day = 0
        while daily.pick(pool, day) ~= "basic-motions-01" do
          day = day + 1
        end
        os.time = function()
          return day * 86400
        end
      ]])
      player:lua("require('vimdojo.app').start_daily()")
      player:wait_for("(" .. CURRENT .. " or {}).ready")
      player:type("jjjll")
      player:wait_for_record("basic-motions-01")

      local card =
        table.concat(player:lua("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"), "\n")
      assert.is_truthy(card:find("You    jjjll", 1, true))
      assert.is_truthy(card:find("shown once today's daily ends", 1, true))
      assert.is_falsy(card:find("Learn", 1, true))
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

  describe("with lessons", function()
    local BUFFER = "table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n')"
    local LESSON_SHOWING = BUFFER .. ":find('Vim edits read like sentences', 1, true) ~= nil"
    local MENU_SHOWING = BUFFER .. ":find('Baby steps', 1, true) ~= nil"

    before_each(function()
      player = player_mod.spawn({ unlock_all = true })
      player:lua("vim.cmd('VimDojo')")
    end)

    --- Searching from the pack's title skips today's daily, which may be the same level.
    ---@param pack string The pack's title line, as a pattern.
    ---@param title string A level's title.
    local function pick(pack, title)
      player:lua("local pack, title = ...; vim.fn.search(pack); vim.fn.search(title)", pack, title)
      player:input("<CR>")
    end

    it("shows a new pack's lesson before its first level, then starts it", function()
      pick("3\\. Operate", "Kill the typo")
      assert.is_true(player:wait_for(LESSON_SHOWING))
      assert.is_nil(player:lua("return " .. CURRENT))
      player:input("<CR>")
      assert.is_true(player:wait_for("(" .. CURRENT .. " or {}).ready"))
      assert.are.equal("operate-01", player:lua("return " .. CURRENT_LEVEL .. ".id"))
    end)

    it("goes back to the menu from that lesson with q", function()
      pick("3\\. Operate", "Kill the typo")
      player:input("q")
      assert.is_true(player:wait_for(MENU_SHOWING))
    end)

    it("skips the lesson once one of the pack's levels is solved", function()
      player:lua("vim.cmd('VimDojo quit')")
      assert.is_true(player:start("operate-01"))
      player:type("ffdw")
      player:wait_for_record("operate-01")
      player:lua("vim.cmd('VimDojo')")
      pick("3\\. Operate", "Security through deletion")
      assert.is_true(player:wait_for("(" .. CURRENT .. " or {}).ready"))
    end)

    it("shows a lesson over the menu with L, and q comes back to it", function()
      player:lua("vim.fn.search('3\\\\. Operate')")
      player:input("L")
      assert.is_true(player:wait_for(LESSON_SHOWING))
      player:input("q")
      assert.is_true(player:wait_for(MENU_SHOWING))
    end)

    it("shows no lesson for a pack without one", function()
      pick("12\\. Boss Levels", "Spreadsheet to docs")
      assert.is_true(player:wait_for("(" .. CURRENT .. " or {}).ready"))
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
