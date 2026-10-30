-- Writes verifier/manifest.json: every shipped level's hash and whether it can
-- be ranked. The API and the verifier read levels' identities from it, and
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
      ('    "%s": {\n      "hash": "%s",\n      "ranked": %s\n    }'):format(
        level.id,
        level_hash.of(level),
        tostring(pack.track ~= UNRANKED_TRACK)
      )
    )
  end
end
table.sort(entries)

local text = '{\n  "levels": {\n' .. table.concat(entries, ",\n") .. "\n  }\n}\n"
vim.fn.writefile(vim.split(text, "\n", { plain = true, trimempty = true }), OUTPUT)
print(("wrote %d levels to verifier/manifest.json"):format(#entries))
