-- Proves every shipped level is solvable in real Neovim and that its par is
-- honest: the reference solution must reach the goal within par_keys.
local challenges = require("vimdojo.challenges")
local goals = require("vimdojo.goals")
local keys = require("vimdojo.keys")

local packs = assert(challenges.load_dir())

---@return vimdojo.Snapshot
local function snapshot()
  return {
    lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
    cursor = vim.api.nvim_win_get_cursor(0),
  }
end

---@param level vimdojo.Level
local function open_level(level)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, level.start_text)
  vim.api.nvim_win_set_cursor(0, level.cursor_start)
end

---@param notation string
local function type_keys(notation)
  local raw = vim.api.nvim_replace_termcodes(notation, true, false, true)
  -- "x" runs the keys to completion (and leaves insert mode), "t" treats them
  -- as typed so they behave like a player's input, "n" ignores mappings so
  -- levels are judged against stock Vim behavior.
  vim.api.nvim_feedkeys(raw, "xtn", false)
end

for _, pack in ipairs(packs) do
  describe(pack.pack, function()
    for _, level in ipairs(pack.levels) do
      describe(level.id, function()
        before_each(function()
          open_level(level)
        end)

        after_each(function()
          vim.cmd("stopinsert")
          vim.api.nvim_buf_delete(0, { force = true })
        end)

        it("is not solved before any key is pressed", function()
          assert.is_false(goals.is_met(level.goal, snapshot(), level.start_text))
        end)

        it("is solved by its reference solution", function()
          type_keys(level.solution)
          local state = snapshot()
          assert.is_true(
            goals.is_met(level.goal, state, level.start_text),
            ("solution %q left lines=%s cursor=%s"):format(
              level.solution,
              vim.inspect(state.lines),
              vim.inspect(state.cursor)
            )
          )
        end)

        it("has a solution within par", function()
          assert.is_true(keys.count(level.solution) <= level.par_keys)
        end)
      end)
    end
  end)
end
