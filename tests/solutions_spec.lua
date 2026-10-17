-- Proves every shipped level is solvable in the clean room, the same
-- environment players get: the reference solution is typed key by key into a
-- real Neovim, must reach the goal, and must be counted as exactly its own
-- length (which also checks key capture through the terminal) within par.
local challenges = require("vimdojo.challenges")
local goals = require("vimdojo.goals")
local keys = require("vimdojo.keys")
local player_mod = require("player")

local packs = assert(challenges.load_dir())

for _, pack in ipairs(packs) do
  describe(pack.pack, function()
    for _, level in ipairs(pack.levels) do
      describe(level.id, function()
        it("has a solution within par", function()
          assert.is_true(keys.count(level.solution) <= level.par_keys)
        end)

        it("is solved in the clean room by its reference solution", function()
          local player = player_mod.spawn({ unlock_all = true })
          local ok, err = pcall(function()
            assert.is_true(player:start(level.id), "room never became ready")
            local start = player:snapshot()
            assert.is_false(
              goals.is_met(level.goal, start, level.start_text),
              "the goal is already met before any key is pressed"
            )

            player:type(level.solution)

            local record = player:wait_for_record(level.id)
            local final = player:lua(
              "local p = require('vimdojo.app').current(); return p and p.room:snapshot()"
            )
            assert.is_truthy(
              record,
              ("solution %q did not solve it; final state %s"):format(
                level.solution,
                vim.inspect(final)
              )
            )
            assert.are.equal(keys.count(level.solution), record.best_keys)
          end)
          player:stop()
          assert(ok, err)
        end)
      end)
    end
  end)
end
