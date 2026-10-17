-- Loads and validates challenge packs from challenges/*.json.
--
-- The JSON Schema in challenges/schema.json is the authoritative contract and
-- is enforced in CI. The checks here are a lightweight runtime subset so a
-- broken or hand-edited pack produces a readable error instead of a crash
-- mid-game.
local check = require("vimdojo.check")
local goals = require("vimdojo.goals")

local M = {}

---@class vimdojo.Level
---@field id string
---@field title string
---@field description string
---@field start_text string[]
---@field cursor_start integer[] [line, col]: 1-based line, 0-based byte column.
---@field goal vimdojo.Goal
---@field par_keys integer
---@field par_seconds number
---@field hint string
---@field solution string
---@field teaches string[]
---@field web_demo boolean|nil

---@class vimdojo.Pack
---@field pack string
---@field title string
---@field description string|nil
---@field order integer
---@field levels vimdojo.Level[]

---@return string
function M.default_dir()
  local this_file = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(this_file, ":p:h:h:h") .. "/challenges"
end

---@param level table
---@return string|nil
local function cursor_start_error(level)
  local cursor = level.cursor_start
  if type(cursor) ~= "table" or #cursor ~= 2 then
    return "cursor_start must be [line, col]"
  end
  local line, col = cursor[1], cursor[2]
  if not (check.is_integer(line) and check.is_integer(col)) then
    return "cursor_start must contain integers"
  end
  if type(level.start_text) ~= "table" or line < 1 or line > #level.start_text then
    return "cursor_start line is outside start_text"
  end
  -- Normal mode can rest on column 0 of an empty line, otherwise only on an
  -- existing byte.
  local max_col = math.max(#level.start_text[line] - 1, 0)
  if col < 0 or col > max_col then
    return "cursor_start col is outside its line"
  end
end

---@param level table
---@return string[]
local function level_errors(level)
  local errors = {}
  local function expect(ok, message)
    if not ok then
      table.insert(errors, message)
    end
  end

  for _, field in ipairs({ "id", "title", "description", "hint", "solution" }) do
    expect(check.is_non_empty_string(level[field]), field .. " must be a non-empty string")
  end
  expect(check.is_string_list(level.start_text), "start_text must be a non-empty array of strings")
  expect(check.is_string_list(level.teaches), "teaches must be a non-empty array of strings")
  expect(check.is_integer(level.par_keys) and level.par_keys >= 1, "par_keys must be >= 1")
  expect(
    type(level.par_seconds) == "number" and level.par_seconds > 0,
    "par_seconds must be a positive number"
  )
  expect(level.web_demo == nil or type(level.web_demo) == "boolean", "web_demo must be a boolean")

  local cursor_error = cursor_start_error(level)
  expect(cursor_error == nil, cursor_error)
  local goal_error = goals.validate(level.goal)
  expect(goal_error == nil, "goal: " .. tostring(goal_error))
  return errors
end

--- Validates one decoded pack. Cross-pack rules (unique ids and orders) are
--- checked by `load_dir`.
---@param pack any
---@return string[] errors Empty when the pack is valid.
function M.validate_pack(pack)
  if type(pack) ~= "table" then
    return { "pack must be an object" }
  end
  local errors = {}
  if not check.is_non_empty_string(pack.pack) then
    table.insert(errors, "pack must be a non-empty string")
  end
  if not check.is_non_empty_string(pack.title) then
    table.insert(errors, "title must be a non-empty string")
  end
  if not (check.is_integer(pack.order) and pack.order >= 1) then
    table.insert(errors, "order must be an integer >= 1")
  end
  if type(pack.levels) ~= "table" or #pack.levels == 0 then
    table.insert(errors, "levels must be a non-empty array")
    return errors
  end
  for index, level in ipairs(pack.levels) do
    local label = ("levels[%d]"):format(index)
    if type(level) ~= "table" then
      table.insert(errors, label .. ": must be an object")
    else
      label = ("%s (%s)"):format(label, tostring(level.id))
      for _, message in ipairs(level_errors(level)) do
        table.insert(errors, label .. ": " .. message)
      end
    end
  end
  return errors
end

---@param text string
---@return vimdojo.Pack|nil pack
---@return string|nil err
function M.decode(text)
  local ok, decoded = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
  if not ok then
    return nil, "invalid JSON: " .. tostring(decoded)
  end
  local errors = M.validate_pack(decoded)
  if #errors > 0 then
    return nil, table.concat(errors, "\n")
  end
  return decoded
end

---@param path string
---@return string|nil content
---@return string|nil err
local function read_file(path)
  local file, open_err = io.open(path, "rb")
  if not file then
    return nil, open_err
  end
  local content = file:read("*a")
  file:close()
  return content
end

---@param packs vimdojo.Pack[]
---@return string[]
local function cross_pack_errors(packs)
  local errors = {}
  local seen_levels, seen_packs, seen_orders = {}, {}, {}
  for _, pack in ipairs(packs) do
    if seen_packs[pack.pack] then
      table.insert(errors, ("duplicate pack id %q"):format(pack.pack))
    end
    if seen_orders[pack.order] then
      table.insert(
        errors,
        ("packs %q and %q share order %d"):format(seen_orders[pack.order], pack.pack, pack.order)
      )
    end
    seen_packs[pack.pack] = true
    seen_orders[pack.order] = pack.pack
    for _, level in ipairs(pack.levels) do
      if seen_levels[level.id] then
        table.insert(errors, ("duplicate level id %q"):format(level.id))
      end
      seen_levels[level.id] = true
    end
  end
  return errors
end

--- Loads every pack file (`*.json` except `schema.json`) in `dir`, sorted by
--- `order`.
---@param dir string|nil Defaults to the plugin's own challenges/ directory.
---@return vimdojo.Pack[]|nil packs
---@return string|nil err
function M.load_dir(dir)
  dir = dir or M.default_dir()
  local paths = vim.fn.glob(dir .. "/*.json", false, true)
  local packs, errors = {}, {}
  for _, path in ipairs(paths) do
    if vim.fn.fnamemodify(path, ":t") ~= "schema.json" then
      local content, read_err = read_file(path)
      local pack, decode_err = nil, read_err
      if content then
        pack, decode_err = M.decode(content)
      end
      if pack then
        table.insert(packs, pack)
      else
        table.insert(errors, ("%s: %s"):format(path, decode_err))
      end
    end
  end
  vim.list_extend(errors, cross_pack_errors(packs))
  if #errors > 0 then
    return nil, table.concat(errors, "\n")
  end
  if #packs == 0 then
    return nil, "no challenge packs found in " .. dir
  end
  table.sort(packs, function(a, b)
    return a.order < b.order
  end)
  return packs
end

return M
