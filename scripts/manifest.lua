-- Writes verifier/manifest.json: every shipped level's hash, its par in keys,
-- whether it can be ranked, whether it's in the daily's pool from before the daily
-- pack (the demo levels outside it), and, for the daily pack's levels, their
-- difficulty and the pack's start date. The overall board measures players against par. The API and the verifier read levels' identities from it, and
-- because it is committed, a pull request that would reset a level's board
-- shows that in its diff.
--
-- Usage: make manifest
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
local challenges = require("vimdojo.challenges")
local daily = require("vimdojo.daily")
local level_hash = require("vimdojo.level_hash")

-- Setup levels stay unranked until their probes run out of process (PLAN-v3, L5).
local UNRANKED_TRACK = "setup"
local OUTPUT = root .. "/verifier/manifest.json"

local packs = assert(challenges.load_dir(root .. "/challenges"))
local legacy = {}
for _, id in ipairs(daily.pool(packs)) do
  legacy[id] = true
end

local entries = {}
for _, pack in ipairs(packs) do
  for _, level in ipairs(pack.levels) do
    local difficulty = level.difficulty and ('      "difficulty": %d,\n'):format(level.difficulty)
      or ""
    table.insert(
      entries,
      ('    "%s": {\n      "daily": %s,\n%s      "hash": "%s",\n      "par_keys": %d,\n      "ranked": %s\n    }'):format(
        level.id,
        tostring(legacy[level.id] == true),
        difficulty,
        level_hash.of(level),
        level.par_keys,
        tostring(pack.track ~= UNRANKED_TRACK)
      )
    )
  end
end
table.sort(entries)

local daily_pack = challenges.daily_pack(packs)
local start = daily_pack and ('  "daily_start": "%s",\n'):format(daily_pack.daily_start) or ""
local text = "{\n" .. start .. '  "levels": {\n' .. table.concat(entries, ",\n") .. "\n  }\n}\n"
vim.fn.writefile(vim.split(text, "\n", { plain = true, trimempty = true }), OUTPUT)
print(("wrote %d levels to verifier/manifest.json"):format(#entries))
