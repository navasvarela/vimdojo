local player_mod = require("player")
local LEVEL = "basic-motions-01"
local function panel(n, cursorline)
  return ([[local ui = require("vimdojo.ui"); local l = {}; for i = 1, %d do l[i] = "line " .. i end
    local p = ui.open_panel({ title = " t ", lines = l, footer = " f " }); vim.wo[p.win].cursorline = %s]]):format(n, tostring(cursorline))
end
local CASES = {
  { "help then quit", "vim.cmd('VimDojo help')" },
  { "short panel", panel(5, true) },
  { "short panel no cursorline", panel(5, false) },
  { "20 lines", panel(20, true) },
  { "40 lines", panel(40, true) },
  { "80 lines", panel(80, true) },
  { "help, then wait 1s", "vim.cmd('VimDojo help')", 1000 },
  { "board-size 40 no cursorline", panel(40, false) },
}
describe("windows crash", function()
  for _, case in ipairs(CASES) do
    it(case[1], function()
      local out = {}
      for i = 1, 4 do
        local player = player_mod.spawn({})
        player:start(LEVEL)
        player:lua(case[2])
        if case[3] then vim.wait(case[3]) end
        local info = player:lua("return { lines = vim.o.lines, columns = vim.o.columns, h = vim.api.nvim_win_get_height(0) }")
        local ok, err = pcall(player.lua, player, "require('vimdojo.app').quit()")
        vim.wait(300)
        local code = vim.fn.jobwait({ player.chan }, 300)[1]
        table.insert(out, ("%s code=%s size=%dx%d h=%d"):format(ok and "ok" or ("DIED " .. tostring(err):sub(1, 40)), code, info.columns, info.lines, info.h))
        pcall(player.stop, player)
      end
      print("RESULT " .. case[1] .. ": " .. table.concat(out, " | "))
    end)
  end
end)
