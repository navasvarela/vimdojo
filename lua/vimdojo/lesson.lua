-- A pack's lesson: the idea behind its levels and the commands they teach, read
-- before the first level. Packs without one still load; they just have nothing to show.
local check = require("vimdojo.check")

local M = {}

---@class vimdojo.LessonExample
---@field before string One line, before the keys.
---@field cursor integer 0-based byte column of the cursor in `before`.
---@field keys string In key notation, as a level's solution is.
---@field after string The line once the keys have run.

---@class vimdojo.LessonCommand
---@field keys string
---@field text string What it does.
---@field example vimdojo.LessonExample|nil

---@class vimdojo.Lesson
---@field intro string[] Paragraphs.
---@field commands vimdojo.LessonCommand[]
---@field help string[] :help tags to read next.

---@param example any
---@return string|nil
local function example_error(example)
  if type(example) ~= "table" then
    return "must be an object"
  end
  if not check.is_non_empty_string(example.before) or type(example.after) ~= "string" then
    return "needs a non-empty before and an after"
  end
  if not check.is_non_empty_string(example.keys) then
    return "needs non-empty keys"
  end
  if
    not check.is_integer(example.cursor)
    or example.cursor < 0
    or example.cursor >= #example.before
  then
    return "cursor must be a byte column inside before"
  end
end

---@param commands any
---@return string[]
local function command_errors(commands)
  if type(commands) ~= "table" or #commands == 0 then
    return { "lesson commands must be a non-empty array" }
  end
  local errors = {}
  for index, command in ipairs(commands) do
    local label = ("lesson commands[%d]"):format(index)
    if
      type(command) ~= "table"
      or not check.is_non_empty_string(command.keys)
      or not check.is_non_empty_string(command.text)
    then
      table.insert(errors, label .. " needs non-empty keys and text")
    elseif command.example ~= nil then
      local err = example_error(command.example)
      if err then
        table.insert(errors, ("%s (%s): example %s"):format(label, command.keys, err))
      end
    end
  end
  return errors
end

--- A lesson that skips a command its levels teach leaves the player where they were
--- without one, so every `teaches` entry must be one of its commands.
---@param lesson vimdojo.Lesson
---@param levels vimdojo.Level[]
---@return string[]
local function coverage_errors(lesson, levels)
  local covered = {}
  for _, command in ipairs(lesson.commands) do
    covered[command.keys] = true
  end
  local errors = {}
  for _, level in ipairs(levels) do
    for _, keys in ipairs(type(level.teaches) == "table" and level.teaches or {}) do
      if not covered[keys] then
        table.insert(
          errors,
          ("lesson doesn't cover %s, which %s teaches"):format(keys, tostring(level.id))
        )
      end
    end
  end
  return errors
end

--- Validates a pack's lesson against the pack's levels.
---@param lesson any
---@param levels vimdojo.Level[]
---@return string[] errors Empty when there is no lesson or it is valid.
function M.errors(lesson, levels)
  if lesson == nil then
    return {}
  end
  if type(lesson) ~= "table" then
    return { "lesson must be an object" }
  end
  local errors = {}
  if not check.is_string_list(lesson.intro) then
    table.insert(errors, "lesson intro must be a non-empty array of paragraphs")
  end
  if not check.is_string_list(lesson.help) then
    table.insert(errors, "lesson help must be a non-empty array of :help tags")
  end
  local command_errs = command_errors(lesson.commands)
  vim.list_extend(errors, command_errs)
  if #command_errs == 0 then
    vim.list_extend(errors, coverage_errors(lesson, levels))
  end
  return errors
end

return M
