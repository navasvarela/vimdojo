-- Shows a pack's lesson (see lesson.lua) in a panel, from the menu or before the
-- pack's first level.
local readable = require("vimdojo.keys").readable
local ui = require("vimdojo.ui")

local M = {}

-- Keeps the panel within an 80-column screen with its border and indent.
local TEXT_WIDTH = 70
local INDENT = "  "
local EXAMPLE_GAP = "   "
-- Keys up to this wide share a column with the text. Longer ones, such as a concept
-- like "macro stops on failure", get a line of their own so the column stays narrow.
local KEYS_COLUMN_MAX = 8

---@class vimdojo.LessonRows
---@field lines string[]
---@field highlights vimdojo.Highlight[]

---@param text string
---@param byte integer 0-based.
---@return integer Bytes in the UTF-8 character starting at `byte`, 1 past the end.
local function char_length(text, byte)
  local char = vim.fn.strcharpart(text:sub(byte + 1), 0, 1)
  return math.max(1, #char)
end

---@param commands vimdojo.LessonCommand[]
---@return integer
local function keys_width(commands)
  local width = 0
  for _, command in ipairs(commands) do
    local keys = vim.fn.strdisplaywidth(command.keys)
    if keys <= KEYS_COLUMN_MAX then
      width = math.max(width, keys)
    end
  end
  return width + 3
end

---@param rows vimdojo.LessonRows
---@param col integer 0-based byte column in the last line where `text` starts.
---@param text string The text the cursor is drawn on.
---@param byte integer The cursor's byte column in `text`.
local function add_cursor(rows, col, text, byte)
  table.insert(rows.highlights, {
    line = #rows.lines - 1,
    col = col + byte,
    end_col = col + byte + char_length(text, byte),
    group = "VimDojoCursor",
  })
end

--- The line before and after the keys, with the cursor drawn where the keys start
--- and, for a motion, where it ends up.
---@param rows vimdojo.LessonRows
---@param indent string
---@param example vimdojo.LessonExample
local function add_example(rows, indent, example)
  local keys = readable(example.keys)
  local keys_col = #indent + #example.before + #EXAMPLE_GAP
  local after_col = keys_col + #keys + #EXAMPLE_GAP
  ui.add_line(rows, indent .. example.before .. EXAMPLE_GAP .. keys .. EXAMPLE_GAP .. example.after)
  add_cursor(rows, #indent, example.before, example.cursor)
  table.insert(rows.highlights, {
    line = #rows.lines - 1,
    col = keys_col,
    end_col = keys_col + #keys,
    group = "VimDojoStar",
  })
  if example.cursor_after then
    add_cursor(rows, after_col, example.after, example.cursor_after)
  end
end

---@param rows vimdojo.LessonRows
---@param keys string
local function highlight_keys(rows, keys)
  table.insert(rows.highlights, {
    line = #rows.lines - 1,
    col = #INDENT,
    end_col = #INDENT + #keys,
    group = "VimDojoTitle",
  })
end

---@param rows vimdojo.LessonRows
---@param commands vimdojo.LessonCommand[]
local function add_commands(rows, commands)
  local width = keys_width(commands)
  local indent = INDENT .. string.rep(" ", width)
  for _, command in ipairs(commands) do
    local text = ui.wrap(command.text, TEXT_WIDTH - width)
    if vim.fn.strdisplaywidth(command.keys) > KEYS_COLUMN_MAX then
      ui.add_line(rows, INDENT .. command.keys)
    else
      ui.add_line(rows, INDENT .. ui.pad(command.keys, width) .. table.remove(text, 1))
    end
    highlight_keys(rows, command.keys)
    for _, line in ipairs(text) do
      ui.add_line(rows, indent .. line)
    end
    if command.example then
      add_example(rows, indent, command.example)
    end
  end
end

local HELP_LABEL = "More: "

--- The :help tags, wrapped between tags so a tag is never split from its :help.
---@param tags string[]
---@return string[]
local function help_lines(tags)
  local lines, line = {}, INDENT .. HELP_LABEL
  local continued = INDENT .. string.rep(" ", #HELP_LABEL)
  for index, tag in ipairs(tags) do
    local item = ":help " .. tag
    local candidate = index == 1 and line .. item or line .. " · " .. item
    if index > 1 and vim.fn.strdisplaywidth(candidate) > #INDENT + TEXT_WIDTH then
      table.insert(lines, line)
      line = continued .. item
    else
      line = candidate
    end
  end
  table.insert(lines, line)
  return lines
end

---@param lesson vimdojo.Lesson
---@return string[] lines
---@return vimdojo.Highlight[] highlights
function M.content(lesson)
  ---@type vimdojo.LessonRows
  local rows = { lines = { "" }, highlights = {} }
  for _, paragraph in ipairs(lesson.intro) do
    for _, line in ipairs(ui.wrap(paragraph, TEXT_WIDTH)) do
      ui.add_line(rows, INDENT .. line)
    end
    ui.add_line(rows, "")
  end
  add_commands(rows, lesson.commands)
  ui.add_line(rows, "")
  for _, line in ipairs(help_lines(lesson.help)) do
    ui.add_line(rows, line, "VimDojoMuted")
  end
  ui.add_line(rows, "")
  return rows.lines, rows.highlights
end

---@class vimdojo.LessonActions
---@field start fun()|nil Plays the level the lesson was shown before.
---@field back fun()|nil Where q goes instead of only closing the panel.

---@param title string The pack's.
---@param lesson vimdojo.Lesson
---@param actions vimdojo.LessonActions|nil
function M.open(title, lesson, actions)
  actions = actions or {}
  ui.define_highlights()
  local lines, highlights = M.content(lesson)
  local panel = ui.open_panel({
    title = (" %s · lesson "):format(title),
    lines = lines,
    highlights = highlights,
    footer = actions.start and " <CR> start the level · q back to the menu " or " q close ",
  })
  local function back()
    panel.close()
    if actions.back then
      actions.back()
    end
  end
  local mappings = { q = back, ["<Esc>"] = back }
  if actions.start then
    mappings["<CR>"] = function()
      panel.close()
      actions.start()
    end
  end
  ui.map(panel.buf, mappings)
end

return M
