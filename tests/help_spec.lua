local helpers = require("helpers")
local help = require("vimdojo.help")
local player_mod = require("player")
local scoring = require("vimdojo.scoring")
local vimdojo = require("vimdojo")

-- An 80-column screen, less the 4 columns open_panel() leaves and its 2 of padding.
local MAX_LINE_WIDTH = 74
local DEFAULT_CONTROLS = { hint = "<leader>h", reset = "<leader>r", quit = "<Esc><Esc>" }

---@param overrides table|nil
---@return string
local function help_text(overrides)
  local facts = vim.tbl_extend(
    "force",
    { controls = DEFAULT_CONTROLS, leader = "\\", online_enabled = false },
    overrides or {}
  )
  return table.concat(help.content(facts).lines, "\n")
end

---@param text string
---@param needle string
---@return boolean
local function contains(text, needle)
  return text:find(needle, 1, true) ~= nil
end

describe("the help text", function()
  it("lists every subcommand", function()
    local text = help_text()
    for _, name in ipairs(vimdojo.subcommands()) do
      assert.is_true(contains(text, ":VimDojo " .. name), name .. " is missing from the help")
    end
  end)

  it("takes the scoring numbers from the game", function()
    local text = help_text()
    assert.is_true(contains(text, ("%g x par keys"):format(scoring.TWO_STAR_KEY_FACTOR)))
    assert.is_true(contains(text, ("up to %d:"):format(scoring.MAX_POINTS)))
    assert.is_true(contains(text, ("%d%% for keys"):format(scoring.KEY_WEIGHT * 100)))
    assert.is_true(contains(text, ("%d%% for time"):format(scoring.TIME_WEIGHT * 100)))
    assert.is_true(contains(text, ("multiplies points by %g"):format(scoring.HINT_POINTS_FACTOR)))
  end)

  it("shows the controls as this player configured them", function()
    local text = help_text({ controls = { hint = "gh", reset = "gr", quit = "gq" } })
    for _, lhs in ipairs({ "gh", "gr", "gq" }) do
      assert.is_true(contains(text, lhs))
    end
    assert.is_false(contains(text, "<leader>"))
  end)

  it("says what <leader> is when a control uses it", function()
    assert.is_true(contains(help_text({ leader = "<Space>" }), "<leader> is <Space> here"))
  end)

  it("says how to turn the leaderboards on while they're off", function()
    local text = help_text({ online_enabled = false })
    assert.is_true(contains(text, "LEADERBOARDS: OFF"))
    assert.is_true(contains(text, "online = { enabled = true }"))
    assert.is_true(contains(text, ":VimDojo login"))
  end)

  it("doesn't ask to turn the leaderboards on when they're on", function()
    local text = help_text({ online_enabled = true })
    assert.is_true(contains(text, "LEADERBOARDS: ON"))
    assert.is_false(contains(text, "online = { enabled = true }"))
    assert.is_true(contains(text, ":VimDojo login"))
  end)

  it("points at the manual, which has the sections it summarises", function()
    assert.is_true(contains(help_text(), ":help vimdojo"))
    local manual = table.concat(vim.fn.readfile(helpers.root .. "/doc/vimdojo.txt"), "\n")
    for _, name in ipairs(vimdojo.subcommands()) do
      assert.is_true(contains(manual, "\n    " .. name), name .. " is missing from the manual")
    end
  end)

  it("fits an 80-column screen without wrapping", function()
    local rows = help.content({
      controls = DEFAULT_CONTROLS,
      leader = "\\",
      online_enabled = false,
    })
    for _, line in ipairs(rows.lines) do
      assert.is_true(vim.fn.strdisplaywidth(line) <= MAX_LINE_WIDTH, line)
    end
  end)
end)

describe("the help panel", function()
  local HELP_OPEN = "require('vimdojo.help').is_open()"
  local BUFFER_TEXT = "table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n')"
  local player

  before_each(function()
    player = player_mod.spawn()
  end)

  after_each(function()
    player:stop()
  end)

  it("opens and closes with :VimDojo help", function()
    player:lua("vim.cmd('VimDojo help')")
    assert.is_true(player:lua("return " .. HELP_OPEN))
    assert.is_true(contains(player:lua("return " .. BUFFER_TEXT), "HOW TO PLAY"))
    player:lua("vim.cmd('VimDojo help')")
    assert.is_false(player:lua("return " .. HELP_OPEN))
  end)

  it("needs neither the level packs nor the network", function()
    player:lua("vim.cmd('VimDojo help')")
    assert.is_nil(player:lua("return package.loaded['vimdojo.online']"))
    assert.is_nil(player:lua("return require('vimdojo.app').progress()"))
  end)

  for _, key in ipairs({ "q", "<Esc>", "?" }) do
    it("closes with " .. key, function()
      player:lua("vim.cmd('VimDojo help')")
      player:input(key)
      assert.is_true(player:wait_for("not " .. HELP_OPEN))
    end)
  end

  it("opens with ? on the menu and goes back to it", function()
    player:lua("vim.cmd('VimDojo')")
    player:input("?")
    assert.is_true(player:wait_for(HELP_OPEN))
    player:input("q")
    assert.is_true(player:wait_for("not " .. HELP_OPEN))
    assert.is_true(contains(player:lua("return " .. BUFFER_TEXT), "Baby steps"))
  end)

  it("opens with ? on the results card and goes back to it", function()
    assert.is_true(player:start("basic-motions-01"))
    player:type("jjjll")
    player:wait_for_record("basic-motions-01")
    assert.is_true(player:wait_for("vim.bo.buftype == 'nofile'"))
    player:input("?")
    assert.is_true(player:wait_for(HELP_OPEN))
    player:input("q")
    assert.is_true(player:wait_for("not " .. HELP_OPEN))
    assert.is_true(contains(player:lua("return " .. BUFFER_TEXT), "points"))
  end)

  -- The way a player gets there: out of Terminal mode, then the command typed.
  it("leaves a level running, its keys uncounted, and hands the keys back", function()
    local KEYS = "require('vimdojo.app').current().session.keys"
    assert.is_true(player:start("basic-motions-01"))
    player:type("j")
    assert.is_true(player:wait_for(KEYS .. " == 1"))
    player:input("<C-\\><C-n>")
    assert.is_true(player:wait_for("vim.api.nvim_get_mode().mode == 'nt'"))
    local keys_before = player:lua("return " .. KEYS)

    player:input(":VimDojo help<CR>")
    assert.is_true(player:wait_for(HELP_OPEN))
    assert.are.equal("n", player:lua("return vim.api.nvim_get_mode().mode"))
    player:input("j")
    player:input("q")
    assert.is_true(player:wait_for("not " .. HELP_OPEN))

    assert.is_true(player:wait_for("vim.api.nvim_get_mode().mode == 't'"))
    assert.are.equal(keys_before, player:lua("return " .. KEYS))
    player:type("jjll")
    assert.is_truthy(player:wait_for_record("basic-motions-01"))
  end)
end)
