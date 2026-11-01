-- Proves every shipped level is solvable in the clean room, the same
-- environment players get: the reference solution is typed key by key into a
-- real Neovim, must reach the goal, and must be counted as exactly its own
-- length (which also checks key capture through the terminal) within par.
local challenges = require("vimdojo.challenges")
local compat = require("vimdojo.compat")
local goals = require("vimdojo.goals")
local helpers = require("helpers")
local keylog = require("vimdojo.keylog")
local keys = require("vimdojo.keys")
local level_hash = require("vimdojo.level_hash")
local player_mod = require("player")

-- Columns of the room's command line in the player's 80-column terminal. A longer
-- command wraps, so whatever it prints ends in a "Press ENTER" prompt: measured on
-- 0.12, 59 keys including the colon fit and 60 prompt. The prompt costs a key the
-- par doesn't count, and the room serves no requests until it's dismissed.
local MAX_EX_COMMAND_KEYS = 59

--- The keys of the longest Ex command `solution` runs, colon included. A colon
--- typed in Insert mode counts too if a <CR> follows, which only matters for a
--- line of text too long to fit in the room anyway.
---@param solution string
---@return integer
local function longest_ex_command(solution)
  local longest, length = 0, nil
  for _, key in ipairs(keys.split(solution)) do
    if length and key == "<CR>" then
      longest, length = math.max(longest, length), nil
    elseif length and key == "<Esc>" then
      length = nil
    elseif length then
      length = length + 1
    elseif key == ":" then
      length = 1
    end
  end
  return longest
end

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

            it("has Ex commands that fit on the room's command line", function()
              assert.is_true(
                longest_ex_command(level.solution) <= MAX_EX_COMMAND_KEYS,
                ("an Ex command in %q is over %d keys"):format(level.solution, MAX_EX_COMMAND_KEYS)
              )
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
                  local checked = player:poll(function()
                    local snapshot = player:snapshot()
                    return snapshot and snapshot.config_passed ~= nil and snapshot
                  end)
                  local solved_itself = player:lua(
                    ("return require('vimdojo.app').progress().levels[%q] ~= nil"):format(level.id)
                  )
                  assert.is_false(
                    solved_itself,
                    "the starter config already passes every probe (the level solved itself)"
                  )
                  assert.is_truthy(checked, "the starter config was never checked")
                  assert.is_false(
                    goals.is_met(level.goal, checked, level.start_text),
                    "the starter config already passes every probe"
                  )
                end

                player:type(level.solution)

                local record = player:wait_for_record(level.id)
                local final = player:snapshot()
                local messages = record and "" or player:room_call("messages")
                assert.is_truthy(
                  record,
                  ("solution %q did not solve it; final state %s; messages:%s"):format(
                    level.solution,
                    vim.inspect(final),
                    tostring(messages)
                  )
                )
                assert.are.equal(keys.count(level.solution), record.best_keys)
                -- Setup levels can't rank, so they leave no key log.
                local run = keylog.load(player.keylog_dir, level.id)
                if #goals.probes(level.goal) > 0 then
                  assert.is_nil(run)
                else
                  assert.are.equal(record.best_keys, #run.keys)
                  assert.are.equal(#run.keys, #run.deltas_ms)
                  assert.are.equal(level_hash.of(level), run.level_hash)
                end
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
