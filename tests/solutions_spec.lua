-- Proves every shipped level is solvable in the clean room, the same
-- environment players get: the reference solution is typed key by key into a
-- real Neovim, must reach the goal, and must be counted as exactly its own
-- length (which also checks key capture through the terminal) within par.
local challenges = require("vimdojo.challenges")
local compat = require("vimdojo.compat")
local goals = require("vimdojo.goals")
local helpers = require("helpers")
local keys = require("vimdojo.keys")
local player_mod = require("player")

-- The shipped curriculum, plus fixture packs that exercise every schema
-- feature (presets, options, register goals, version gates).
local sources = {
  { dir = challenges.default_dir(), setup = {} },
  {
    dir = helpers.root .. "/tests/fixtures/packs",
    setup = { challenges_dir = helpers.root .. "/tests/fixtures/packs" },
  },
}

for _, source in ipairs(sources) do
  for _, pack in ipairs(assert(challenges.load_dir(source.dir))) do
    describe(pack.pack, function()
      for _, level in ipairs(pack.levels) do
        if not compat.supports(level, compat.running()) then
          pending(("%s needs Neovim %s"):format(level.id, level.requires.nvim))
        else
          describe(level.id, function()
            it("has a solution within par", function()
              assert.is_true(keys.count(level.solution) <= level.par_keys)
            end)

            it("is solved in the clean room by its reference solution", function()
              local player =
                player_mod.spawn(vim.tbl_extend("force", { unlock_all = true }, source.setup))
              local ok, err = pcall(function()
                assert.is_true(player:start(level.id), "room never became ready")
                local start = player:snapshot()
                assert.is_false(
                  goals.is_met(level.goal, start, level.start_text),
                  "the goal is already met before any key is pressed"
                )
                -- Setup levels get their first sandbox verdict asynchronously,
                -- after the snapshot above; a starter config that already
                -- passes every probe would solve the level with zero keys.
                if #goals.probes(level.goal) > 0 then
                  local checked = player:wait_for(
                    "(function() local s = require('vimdojo.app').current().room:snapshot();"
                      .. " return s and s.config_passed ~= nil and s end)()"
                  )
                  assert.is_truthy(checked, "the starter config was never checked")
                  assert.is_false(
                    goals.is_met(level.goal, checked, level.start_text),
                    "the starter config already passes every probe"
                  )
                end

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
      end
    end)
  end
end
