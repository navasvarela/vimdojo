-- One tip from the keys a player typed: a shorter way to say what they said, such as a
-- count instead of a run of `j`. web/src/game/tips.ts does the same, and
-- tests/fixtures/tips.json pins both.
--
-- Keys are read as commands, so text typed in Insert mode or on the command line
-- never looks like a run of motions:
--   1. Split the keys into commands: [count] then a motion, an operator with its
--      motion, an Insert-mode entry with the text up to <Esc>, or a command line.
--   2. Look for each kind of saving, and keep the biggest.
local keys_module = require("vimdojo.keys")

local M = {}

local INSERT_ENTRIES = {
  i = true,
  a = true,
  o = true,
  I = true,
  A = true,
  O = true,
  s = true,
  S = true,
  C = true,
  R = true,
}
local OPERATORS = { d = true, y = true, c = true, ["<"] = true, [">"] = true, ["="] = true }
local G_OPERATORS = { U = true, u = true, ["~"] = true, ["?"] = true }
-- Commands whose next key is an argument, not a command: `fx`, `ma`, `"a`, `<C-W>j`.
local TAKES_ARGUMENT = {
  f = true,
  t = true,
  F = true,
  T = true,
  r = true,
  m = true,
  ["'"] = true,
  ["`"] = true,
  ["@"] = true,
  q = true,
  ['"'] = true,
  g = true,
  z = true,
  Z = true,
  ["["] = true,
  ["]"] = true,
  ["<C-W>"] = true,
}
-- Text objects take one more key: `iw`, `a(`.
local TEXT_OBJECT = { i = true, a = true }
local COMMAND_LINES = { [":"] = true, ["/"] = true, ["?"] = true }
local ENDS_COMMAND_LINE = { ["<CR>"] = true, ["<Esc>"] = true }
local ARROWS = { ["<Up>"] = true, ["<Down>"] = true, ["<Left>"] = true, ["<Right>"] = true }
-- Runs that a count shortens. Arrows aren't here: the tip for them is to stop using them.
local NOT_REPEATABLE = { insert = true, command_line = true }

local ARROW_TIP =
  "Arrow keys move your hand off the home row: `h` `j` `k` `l` do the same in Normal mode."

---@class vimdojo.TipCommand
---@field count string Digits typed before the command, or "".
---@field keys string The command without its count.
---@field kind "motion"|"insert"|"command_line"
---@field entry string|nil The key that entered Insert mode.
---@field text string[]|nil Keys typed in Insert mode or on the command line.
---@field operator string|nil
---@field motion string|nil

--- A count can't start with 0: on its own, `0` is the motion to the start of the line.
---@param key string|nil
---@param first boolean
---@return boolean
local function is_count_digit(key, first)
  return key ~= nil and key:match("^%d$") ~= nil and not (first and key == "0")
end

---@param keys string[]
---@param pos integer
---@param ends table<string, true>
---@return string[] text
---@return integer next Past the key that ended it.
local function until_escape(keys, pos, ends)
  local text = {}
  while pos <= #keys and not ends[keys[pos]] do
    table.insert(text, keys[pos])
    pos = pos + 1
  end
  return text, pos + 1
end

--- A motion after an operator: `w`, `fx`, `iw`, `gg`, `$`.
---@param keys string[]
---@param pos integer
---@return string motion
---@return integer next
local function read_motion(keys, pos)
  local key = keys[pos] or ""
  if TAKES_ARGUMENT[key] or TEXT_OBJECT[key] then
    return key .. (keys[pos + 1] or ""), pos + 2
  end
  return key, pos + 1
end

---@param keys string[]
---@return vimdojo.TipCommand[]
function M.commands(keys)
  local commands = {}
  local pos = 1
  while pos <= #keys do
    local count = ""
    while is_count_digit(keys[pos], count == "") do
      count = count .. keys[pos]
      pos = pos + 1
    end
    local key = keys[pos]
    if key == nil then
      break
    end
    local command = { count = count, kind = "motion" }
    if INSERT_ENTRIES[key] then
      command.kind, command.entry, command.keys = "insert", key, key
      command.text, pos = until_escape(keys, pos + 1, { ["<Esc>"] = true })
    elseif COMMAND_LINES[key] then
      command.kind, command.keys = "command_line", key
      command.text, pos = until_escape(keys, pos + 1, ENDS_COMMAND_LINE)
    elseif OPERATORS[key] or (key == "g" and G_OPERATORS[keys[pos + 1] or ""]) then
      local operator = key == "g" and key .. keys[pos + 1] or key
      pos = pos + (key == "g" and 2 or 1)
      local motion
      if keys[pos] == key then
        motion, pos = key, pos + 1
      else
        motion, pos = read_motion(keys, pos)
      end
      command.operator, command.motion, command.keys = operator, motion, operator .. motion
      if operator == "c" then
        command.kind, command.entry = "insert", "c"
        command.text, pos = until_escape(keys, pos, { ["<Esc>"] = true })
      end
    elseif TAKES_ARGUMENT[key] then
      command.keys = key .. (keys[pos + 1] or "")
      pos = pos + 2
    else
      command.keys = key
      pos = pos + 1
    end
    table.insert(commands, command)
  end
  return commands
end

---@class vimdojo.Tip
---@field text string
---@field saving integer Keys it would have saved.

--- A run of the same command a count could replace: `jjjj` is `4j`.
---@param commands vimdojo.TipCommand[]
---@return vimdojo.Tip|nil
local function repeated_run(commands)
  local best
  local i = 1
  while i <= #commands do
    local command = commands[i]
    local j = i
    while
      j + 1 <= #commands
      and commands[j + 1].keys == command.keys
      and commands[j + 1].count == ""
      and commands[j + 1].kind == command.kind
    do
      j = j + 1
    end
    local times = j - i + 1
    local length = #keys_module.split(command.keys)
    local saving = times * length - (#tostring(times) + length)
    if
      command.count == ""
      and not NOT_REPEATABLE[command.kind]
      and not ARROWS[command.keys]
      and saving > 0
      and (not best or saving > best.saving)
    then
      best = {
        saving = saving,
        text = ("You typed `%s` %d times in a row: `%d%s` does the same in %d keys."):format(
          command.keys,
          times,
          times,
          command.keys,
          #tostring(times) + length
        ),
      }
    end
    i = j + 1
  end
  return best
end

---@param before vimdojo.TipCommand
---@param after vimdojo.TipCommand
---@return string|nil shorter
local function shorter_pair(before, after)
  if after.kind ~= "insert" then
    return nil
  end
  if before.operator == "d" and before.motion ~= "d" and after.entry == "i" then
    return before.count .. "c" .. before.motion
  end
  local pairs_to_one =
    { x = { i = "s" }, D = { a = "C" }, ["^"] = { i = "I" }, ["$"] = { a = "A" } }
  local shorter = pairs_to_one[before.keys] and pairs_to_one[before.keys][after.entry]
  if shorter and before.count == "" then
    return shorter
  end
end

--- A command and the Insert-mode entry after it that one key does together: `dwi` is `cw`.
---@param commands vimdojo.TipCommand[]
---@return vimdojo.Tip|nil
local function combined_pair(commands)
  for i = 1, #commands - 1 do
    local before, after = commands[i], commands[i + 1]
    local shorter = shorter_pair(before, after)
    if shorter then
      return {
        saving = 1,
        text = ("`%s%s` then `%s` is `%s`, one key shorter."):format(
          before.count,
          before.keys,
          after.entry,
          shorter
        ),
      }
    end
  end
  for _, command in ipairs(commands) do
    if command.entry == "A" and command.text[1] == "<CR>" then
      return { saving = 1, text = "`A` then `<CR>` is `o`, one key shorter." }
    end
  end
end

---@param keys string[]
---@return boolean
local function uses_arrows(keys)
  for _, key in ipairs(keys) do
    if ARROWS[key] then
      return true
    end
  end
  return false
end

--- The tip worth the most keys, or nil when there's nothing useful to say.
---@param keys string[] The attempt's keys, as a key log names them.
---@return string|nil
function M.tip(keys)
  local commands = M.commands(keys)
  local run, pair = repeated_run(commands), combined_pair(commands)
  local best = run
  if pair and (not best or pair.saving > best.saving) then
    best = pair
  end
  if best then
    return best.text
  end
  if uses_arrows(keys) then
    return ARROW_TIP
  end
end

return M
