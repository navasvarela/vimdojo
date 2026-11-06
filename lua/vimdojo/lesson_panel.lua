-- Shows a pack's lesson (see lesson.lua) in a panel, from the menu or before the
-- pack's first level.
local ui = require("vimdojo.ui")

local M = {}

-- Keeps the panel within an 80-column screen with its border and indent.
local TEXT_WIDTH = 70
local INDENT = "  "
local EXAMPLE_GAP = "   "

---@class vimdojo.LessonRows
---@field lines string[]
---@field highlights vimdojo.Highlight[]

---@param text string
---@param byte integer 0-based.
---@return integer Bytes in the UTF-8 character starting at `byte`.
local function char_length(text, byte)
  local char = vim.fn.strcharpart(text:sub(byte + 1), 0, 1)
  return math.max(1, #char)
end

---@param commands vimdojo.LessonCommand[]
---@return integer
local function keys_width(commands)
  local width = 0
  for _, command in ipairs(commands) do
    width = math.max(width, vim.fn.strdisplaywidth(command.keys))
  end
  return width + 3
end

--- The example's line before the keys, with the cursor drawn where the keys start.
---@param rows vimdojo.LessonRows
---@param indent string
---@param example vimdojo.LessonExample
local function add_example(rows, indent, example)
  local keys_col = #indent + #example.before + #EXAMPLE_GAP
  ui.add_line(
    rows,
    indent .. example.before .. EXAMPLE_GAP .. example.keys .. EXAMPLE_GAP .. example.after
  )
  local line = #rows.lines - 1
  local cursor_col = #indent + example.cursor
  table.insert(rows.highlights, {
    line = line,
    col = cursor_col,
    end_col = cursor_col + char_length(example.before, example.cursor),
    group = "VimDojoCursor",
  })
  table.insert(rows.highlights, {
    line = line,
    col = keys_col,
    end_col = keys_col + #example.keys,
    group = "VimDojoStar",
  })
end

---@param rows vimdojo.LessonRows
---@param commands vimdojo.LessonCommand[]
local function add_commands(rows, commands)
  local width = keys_width(commands)
  local indent = INDENT .. string.rep(" ", width)
  for _, command in ipairs(commands) do
    for index, line in ipairs(ui.wrap(command.text, TEXT_WIDTH - width)) do
      if index == 1 then
        ui.add_line(rows, INDENT .. ui.pad(command.keys, width) .. line)
        table.insert(rows.highlights, {
          line = #rows.lines - 1,
          col = #INDENT,
          end_col = #INDENT + #command.keys,
          group = "VimDojoTitle",
        })
      else
        ui.add_line(rows, indent .. line)
      end
    end
    if command.example then
      add_example(rows, indent, command.example)
    end
  end
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
  local tags = vim.tbl_map(function(tag)
    return ":help " .. tag
  end, lesson.help)
  ui.add_line(rows, INDENT .. "More: " .. table.concat(tags, " · "), "VimDojoMuted")
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
