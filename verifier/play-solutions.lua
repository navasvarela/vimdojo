-- Plays every ranked level through the real room (terminal, key capture, goal
-- checks), so the plugin writes its key logs. check-keylogs.ts then replays
-- them. Run by that script, with the output directory in VIMDOJO_KEYLOG_DIR:
--   nvim --headless --noplugin -u tests/minimal_init.lua -c "luafile verifier/play-solutions.lua"
local challenges = require("vimdojo.challenges")
local compat = require("vimdojo.compat")
local goals = require("vimdojo.goals")
local player_mod = require("player")

local dir = assert(vim.env.VIMDOJO_KEYLOG_DIR, "VIMDOJO_KEYLOG_DIR is not set")

local function play(level)
  local player = player_mod.spawn({ unlock_all = true, keylog_dir = dir })
  local ok, err = pcall(function()
    assert(player:start(level.id), "the room never became ready")
    player:type(level.solution)
    assert(player:wait_for_record(level.id), "the solution did not solve it")
  end)
  player:stop()
  return ok, err
end

local failed = false
for _, pack in ipairs(assert(challenges.load_dir())) do
  for _, level in ipairs(pack.levels) do
    if #goals.probes(level.goal) == 0 and compat.supports(level, compat.running()) then
      local ok, err = play(level)
      if not ok then
        failed = true
        io.stderr:write(("%s: %s\n"):format(level.id, tostring(err)))
      end
    end
  end
end
vim.cmd(failed and "cquit 1" or "qall!")
