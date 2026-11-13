-- Par finder for cursor_at levels: searches for the shortest key sequence that
-- reaches each level's goal, using real Neovim motions (see scripts/par_search.lua).
--
--   nvim --headless --noplugin -u NONE -l scripts/par.lua
--
-- For every cursor_at level it reports two optima:
--   taught: using only motions taught so far in the curriculum (the par rule)
--   any:    using every motion in the catalogue
--
-- This is an authoring aid, not a test: confirm surprising results by hand.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.o.swapfile = false

local challenges = require("vimdojo.challenges")
local par_search = dofile(root .. "/scripts/par_search.lua")

local packs = assert(challenges.load_dir())
local optima = par_search.optima(packs)
for _, pack in ipairs(packs) do
  for _, level in ipairs(pack.levels) do
    local found = optima[level.id]
    if found then
      local flag = (found.expected ~= found.par) and "  <-- par mismatch" or ""
      print(
        ("%-18s par %2d | taught %2s %-10s | any %2s %-8s%s"):format(
          level.id,
          found.par,
          tostring(found.taught_cost),
          found.taught_path or "-",
          tostring(found.any_cost),
          found.any_path or "-",
          flag
        )
      )
    end
  end
end
