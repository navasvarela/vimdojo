-- Writes verifier/manifest.json: every shipped level's hash, its par in keys,
-- whether it can be ranked, and whether it's in the daily challenge's pool (the
-- demo levels). The overall board measures players against par. The API and the verifier read levels' identities from it, and
-- because it is committed, a pull request that would reset a level's board
-- shows that in its diff.
--
-- Usage: make manifest
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
local challenges = require("vimdojo.challenges")
local level_hash = require("vimdojo.level_hash")

-- Setup levels stay unranked until their probes run out of process (PLAN-v3, L5).
local UNRANKED_TRACK = "setup"
local OUTPUT = root .. "/verifier/manifest.json"

local entries = {}
for _, pack in ipairs(assert(challenges.load_dir(root .. "/challenges"))) do
  for _, level in ipairs(pack.levels) do
    table.insert(
      entries,
      ('    "%s": {\n      "daily": %s,\n      "hash": "%s",\n      "par_keys": %d,\n      "ranked": %s\n    }'):format(
        level.id,
        tostring(level.web_demo == true),
        level_hash.of(level),
        level.par_keys,
        tostring(pack.track ~= UNRANKED_TRACK)
      )
    )
  end
end
table.sort(entries)

local text = '{\n  "levels": {\n' .. table.concat(entries, ",\n") .. "\n  }\n}\n"
vim.fn.writefile(vim.split(text, "\n", { plain = true, trimempty = true }), OUTPUT)
print(("wrote %d levels to verifier/manifest.json"):format(#entries))
