local challenges = require("vimdojo.challenges")
local lesson = require("vimdojo.lesson")

---@return vimdojo.Lesson
local function valid_lesson()
  return {
    intro = { "Words are things you can move by." },
    commands = {
      {
        keys = "w",
        text = "Move to the start of the next word.",
        example = { before = "hello world", cursor = 0, keys = "dw", after = "world" },
      },
    },
    help = { "word-motions" },
  }
end

local LEVELS = { { id = "sample-01", teaches = { "w" } } }

describe("lesson.errors", function()
  it("accepts a valid lesson, and a pack without one", function()
    assert.are.same({}, lesson.errors(valid_lesson(), LEVELS))
    assert.are.same({}, lesson.errors(nil, LEVELS))
  end)

  local cases = {
    {
      name = "a lesson that isn't an object",
      edit = function()
        return "read the manual"
      end,
      error = "lesson must be an object",
    },
    {
      name = "an empty intro",
      edit = function(l)
        l.intro = {}
      end,
      error = "lesson intro must be a non-empty array of paragraphs",
    },
    {
      name = "no help tags",
      edit = function(l)
        l.help = nil
      end,
      error = "lesson help must be a non-empty array of :help tags",
    },
    {
      name = "no commands",
      edit = function(l)
        l.commands = {}
      end,
      error = "lesson commands must be a non-empty array",
    },
    {
      name = "a command without text",
      edit = function(l)
        l.commands[1].text = ""
      end,
      error = "lesson commands[1] needs non-empty keys and text",
    },
    {
      name = "an example without keys",
      edit = function(l)
        l.commands[1].example.keys = ""
      end,
      error = "lesson commands[1] (w): example needs non-empty keys",
    },
    {
      name = "an example's cursor past the end of the line",
      edit = function(l)
        l.commands[1].example.cursor = #"hello world"
      end,
      error = "lesson commands[1] (w): example cursor must be a byte column inside before",
    },
    {
      name = "an example's cursor_after past the end of its line",
      edit = function(l)
        l.commands[1].example.cursor_after = #"world"
      end,
      error = "lesson commands[1] (w): example cursor_after must be a byte column inside after",
    },
    {
      name = "a command its levels teach but it leaves out",
      edit = function(l)
        l.commands[1].keys = "b"
      end,
      error = "lesson doesn't cover w, which sample-01 teaches",
    },
  }

  for _, case in ipairs(cases) do
    it("rejects " .. case.name, function()
      local value = valid_lesson()
      value = case.edit(value) or value
      assert.are.same({ case.error }, lesson.errors(value, LEVELS))
    end)
  end
end)

---@class vimdojo.ExampleRun
---@field line string
---@field cursor integer 0-based byte column.

--- Runs an example's keys on its line in a scratch buffer, as a player would type them.
---@param example vimdojo.LessonExample
---@return vimdojo.ExampleRun
local function run_example(example)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, { example.before })
  vim.api.nvim_win_set_cursor(0, { 1, example.cursor })
  -- "n" ignores any mappings, "t" makes the keys count as typed, so q records them,
  -- and "x" runs them now rather than when the test yields.
  vim.api.nvim_feedkeys(vim.keycode(example.keys), "ntx", false)
  local run = {
    line = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, true), "\n"),
    cursor = vim.api.nvim_win_get_cursor(0)[2],
  }
  vim.api.nvim_buf_delete(buf, { force = true })
  return run
end

-- A lesson panel has a border and sits on an 80-column screen.
local MAX_LESSON_WIDTH = 78

describe("shipped lessons", function()
  for _, pack in ipairs(assert(challenges.load_dir(challenges.default_dir()))) do
    if pack.lesson then
      it(("%s: fits an 80-column screen"):format(pack.pack), function()
        local lesson_panel = require("vimdojo.lesson_panel")
        for _, line in ipairs(lesson_panel.content(pack.lesson)) do
          assert(vim.fn.strdisplaywidth(line) <= MAX_LESSON_WIDTH, "too wide: " .. line)
        end
      end)
    end

    for _, command in ipairs(pack.lesson and pack.lesson.commands or {}) do
      local example = command.example
      if example then
        it(("%s: %s's example does what it shows"):format(pack.pack, command.keys), function()
          local run = run_example(example)
          assert.are.equal(example.after, run.line)
          if example.cursor_after then
            assert.are.equal(example.cursor_after, run.cursor)
          end
        end)
      end
    end
  end
end)

describe("lesson_panel.content", function()
  local lesson_panel = require("vimdojo.lesson_panel")

  it("lays out the intro, each command and example, and the help tags", function()
    local lines = lesson_panel.content(valid_lesson())
    assert.are.same({
      "",
      "  Words are things you can move by.",
      "",
      "  w   Move to the start of the next word.",
      "      hello world   dw   world",
      "",
      "  More: :help word-motions",
      "",
    }, lines)
  end)

  it("draws the cursor on the example's character at its byte column", function()
    local value = valid_lesson()
    value.commands[1].example = { before = "héllo", cursor = 1, keys = "x", after = "hllo" }
    local lines, highlights = lesson_panel.content(value)
    local cursor = vim.tbl_filter(function(highlight)
      return highlight.group == "VimDojoCursor"
    end, highlights)[1]
    assert.are.equal("é", lines[cursor.line + 1]:sub(cursor.col + 1, cursor.end_col))
  end)

  it("gives keys too wide for the column a line of their own", function()
    local value = valid_lesson()
    table.insert(value.commands, { keys = "macro stops on failure", text = "It stops." })
    local lines = lesson_panel.content(value)
    assert.is_truthy(vim.tbl_contains(lines, "  macro stops on failure"))
    assert.is_truthy(vim.tbl_contains(lines, "      It stops."))
  end)

  it("draws the cursor where a motion leaves it, and shows <lt> as <", function()
    local value = valid_lesson()
    value.commands[1].example =
      { before = "a <b>", cursor = 0, keys = "f<lt>", after = "a <b>", cursor_after = 2 }
    local lines, highlights = lesson_panel.content(value)
    local example = lines[5]
    assert.are.equal("      a <b>   f<   a <b>", example)
    local cursors = vim.tbl_filter(function(highlight)
      return highlight.group == "VimDojoCursor"
    end, highlights)
    assert.are.equal(2, #cursors)
    assert.are.equal(#"      a <b>   f<   a ", cursors[2].col)
  end)
end)
