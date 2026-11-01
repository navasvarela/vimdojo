local player_mod = require("player")
local LEVEL = "basic-motions-01"
local HELP = "vim.cmd('VimDojo help')"
local QUIT = "require('vimdojo.app').quit()"
local PANEL_CLOSE = "require('vimdojo.ui').close_panels()"
local RAW = "local p = require('vimdojo.app').current();"
local CASES = {
  { "A quit, no panel", {}, QUIT },
  { "B help, quit", { HELP }, QUIT },
  { "C help, wait 200, quit", { HELP, 200 }, QUIT },
  { "D help, wait 500, quit", { HELP, 500 }, QUIT },
  { "E help, close it, quit", { HELP, PANEL_CLOSE }, QUIT },
  { "F help, close it, wait 500, quit", { HELP, PANEL_CLOSE, 500 }, QUIT },
  { "G help, stop job only", { HELP }, RAW .. "pcall(vim.fn.jobstop, p.room.job)" },
  { "H help, close room window only", { HELP }, RAW .. "vim.api.nvim_win_close(p.layout.room_win, true)" },
  { "I help, nothing else, wait", { HELP }, "return 1" },
  { "J help, redraw then quit", { HELP, "vim.cmd('redraw!')" }, QUIT },
  { "K help, windows first then deferred stop", { HELP }, RAW .. "local r=p.room; vim.api.nvim_win_close(p.layout.room_win, true); vim.defer_fn(function() pcall(vim.fn.jobstop, r.job) end, 1500)" },
}
describe("windows crash", function()
  for _, case in ipairs(CASES) do
    it(case[1], function()
      local out = {}
      for _ = 1, 3 do
        _G.LAST_EXIT = nil
        local player = player_mod.spawn({})
        player:start(LEVEL)
        local ok, err = pcall(function()
          for _, step in ipairs(case[2]) do
            if type(step) == "number" then vim.wait(step) else player:lua(step) end
          end
          player:lua(case[3])
        end)
        vim.wait(2000)
        local alive = pcall(player.lua, player, "return 1")
        table.insert(out, ("%s alive=%s exit=%s"):format(ok and "ok" or "DIED", tostring(alive), tostring(_G.LAST_EXIT)))
        pcall(player.stop, player)
      end
      print("RESULT " .. case[1] .. ": " .. table.concat(out, " | "))
    end)
  end
end)
