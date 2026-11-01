-- The in-game help panel: how to play, scoring, keys, commands and the online
-- setup, short enough to read between levels. doc/vimdojo.txt stays the manual.
-- Numbers come from scoring.lua and keys from the config, so they can't disagree
-- with the game, and tests/help_spec.lua fails if a subcommand is missing here.
local scoring = require("vimdojo.scoring")
local ui = require("vimdojo.ui")

local M = {}

local KEY_WIDTH = 16

---@alias vimdojo.HelpEntry { [1]: string, [2]: string }

---@type vimdojo.HelpEntry[]
local GAME_COMMANDS = {
  { ":VimDojo", "Open the level menu (or :VimDojo menu)" },
  { ":VimDojo daily", "Play today's daily challenge" },
  { ":VimDojo help", "Open or close this help" },
  { ":VimDojo hint", "Show the current level's hint" },
  { ":VimDojo reset", "Restart the current level" },
  { ":VimDojo quit", "Leave the current level" },
}

---@type vimdojo.HelpEntry[]
local ONLINE_COMMANDS = {
  { ":VimDojo login", "Sign in with GitHub and pick a public handle" },
  { ":VimDojo logout", "Sign out, and revoke this machine's login" },
  { ":VimDojo account", "Show who you're signed in as" },
  { ":VimDojo submit", "Send the best run of every level you've played" },
  { ":VimDojo board", "Show a level's board. Takes a level, or daily" },
  { ":VimDojo scores", "Show your verified bests and places" },
}

---@type vimdojo.HelpEntry[]
local MENU_KEYS = {
  { "<CR>", "Play the level under the cursor" },
  { "q", "Close the menu" },
}

---@type vimdojo.HelpEntry[]
local RESULTS_KEYS = {
  { "n or <CR>", "Next level" },
  { "r", "Retry the level" },
  { "y", "Copy a spoiler-free result to share" },
  { "m", "Back to the menu" },
  { "q", "Quit" },
}

---@type vimdojo.HelpEntry[]
local RESULTS_ONLINE_KEYS = {
  { "s", "Submit the run to the leaderboards" },
  { "b", "Show the level's board" },
}

---@param rows { lines: string[], highlights: vimdojo.Highlight[] }
---@param title string
local function add_heading(rows, title)
  ui.add_line(rows, "")
  ui.add_line(rows, "  " .. title, "VimDojoTitle")
end

---@param rows { lines: string[], highlights: vimdojo.Highlight[] }
---@param entries vimdojo.HelpEntry[]
---@param width integer Display width of the left column.
local function add_entries(rows, entries, width)
  for _, entry in ipairs(entries) do
    ui.add_line(rows, ("    %s  %s"):format(ui.pad(entry[1], width), entry[2]))
  end
end

---@param rows { lines: string[], highlights: vimdojo.Highlight[] }
local function add_how_to_play(rows)
  add_heading(rows, "HOW TO PLAY")
  ui.add_line(rows, "    Reach each level's goal with Vim keys, in as few as you can.")
  ui.add_line(rows, "    The timer starts on your first key. Every physical key counts:")
  ui.add_line(rows, "    d2w is 3 keys and <Esc> is 1.")
  ui.add_line(rows, "    A level is solved as soon as its goal holds in Normal mode.")
  ui.add_line(rows, "    Levels unlock in order, and finishing a pack unlocks the next.")
end

---@param rows { lines: string[], highlights: vimdojo.Highlight[] }
local function add_scoring(rows)
  add_heading(rows, "SCORING")
  ui.add_line(rows, ("    %s  At or under par on both keys and time"):format(ui.stars(3)))
  ui.add_line(
    rows,
    ("    %s  Up to %g x par keys"):format(ui.stars(2), scoring.TWO_STAR_KEY_FACTOR)
  )
  ui.add_line(rows, ("    %s  Solved"):format(ui.stars(1)))
  ui.add_line(
    rows,
    ("    Points go up to %d: %d%% for keys and %d%% for time."):format(
      scoring.MAX_POINTS,
      scoring.KEY_WEIGHT * 100,
      scoring.TIME_WEIGHT * 100
    )
  )
  ui.add_line(
    rows,
    ("    The hint multiplies points by %g and caps the attempt at %d stars."):format(
      scoring.HINT_POINTS_FACTOR,
      scoring.HINTED_MAX_STARS
    )
  )
  ui.add_line(rows, "    Par uses only the motions taught so far, so more Vim can beat it.")
end

---@param rows { lines: string[], highlights: vimdojo.Highlight[] }
---@param controls vimdojo.Controls
---@param leader string What <leader> means in a level, in key notation.
local function add_level_keys(rows, controls, leader)
  add_heading(rows, "KEYS IN A LEVEL")
  add_entries(rows, {
    { controls.hint, "Show the hint" },
    { controls.reset, "Restart the level" },
    { controls.quit, "Leave the level" },
  }, KEY_WIDTH)
  ui.add_line(rows, "    These never count as keystrokes. Any other key is the level's.")
  local names = table.concat({ controls.hint, controls.reset, controls.quit })
  if names:lower():find("<leader>", 1, true) then
    ui.add_line(rows, ("    <leader> is %s here."):format(leader))
  end
end

---@param rows { lines: string[], highlights: vimdojo.Highlight[] }
---@param online_enabled boolean
local function add_online(rows, online_enabled)
  add_heading(rows, online_enabled and "LEADERBOARDS: ON" or "LEADERBOARDS: OFF")
  if online_enabled then
    ui.add_line(rows, "    Run :VimDojo login to sign in, if you haven't yet.")
  else
    ui.add_line(rows, "    Optional. Nothing touches the network until you turn them on:")
    ui.add_line(rows, '      require("vimdojo").setup({ online = { enabled = true } })')
    ui.add_line(rows, "    Then run :VimDojo login.")
  end
  add_entries(rows, ONLINE_COMMANDS, KEY_WIDTH)
  ui.add_line(rows, "    On the results card:")
  add_entries(rows, RESULTS_ONLINE_KEYS, KEY_WIDTH)
end

---@class vimdojo.HelpFacts
---@field controls vimdojo.Controls The keys this player has configured.
---@field leader string What <leader> means in a level, in key notation.
---@field online_enabled boolean

--- Pure, so tests can check it without opening a window.
---@param facts vimdojo.HelpFacts
---@return { lines: string[], highlights: vimdojo.Highlight[] }
function M.content(facts)
  local rows = { lines = {}, highlights = {} }
  add_how_to_play(rows)
  add_scoring(rows)
  add_level_keys(rows, facts.controls, facts.leader)
  add_heading(rows, "KEYS IN THE MENU")
  add_entries(rows, MENU_KEYS, KEY_WIDTH)
  add_heading(rows, "KEYS ON THE RESULTS CARD")
  add_entries(rows, RESULTS_KEYS, KEY_WIDTH)
  add_heading(rows, "COMMANDS")
  add_entries(rows, GAME_COMMANDS, KEY_WIDTH)
  add_online(rows, facts.online_enabled)
  add_heading(rows, "MORE")
  ui.add_line(rows, "    :help vimdojo is the full manual. It opens behind the game's panels.")
  ui.add_line(rows, "")
  return rows
end

---@type vimdojo.Panel|nil
local panel = nil

---@return boolean
function M.is_open()
  return panel ~= nil and vim.api.nvim_win_is_valid(panel.win)
end

function M.close()
  if panel then
    panel.close()
    panel = nil
  end
end

--- Opens the help above whatever is showing, or closes it if it's already open.
--- Closing hands focus back to that window, so a level resumes in Terminal mode.
function M.toggle()
  if M.is_open() then
    M.close()
    return
  end
  local config = require("vimdojo").config
  ui.define_highlights()
  local rows = M.content({
    controls = config.keymaps,
    leader = vim.fn.keytrans(vim.g.mapleader or "\\"),
    online_enabled = config.online.enabled,
  })
  panel = ui.open_panel({
    title = " vimdojo help ",
    lines = rows.lines,
    highlights = rows.highlights,
    footer = " j/k scroll · q close ",
  })
  vim.wo[panel.win].cursorline = false
  ui.map(panel.buf, { q = M.close, ["<Esc>"] = M.close, ["?"] = M.close })
end

return M
