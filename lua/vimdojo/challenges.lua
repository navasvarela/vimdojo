-- Loads and validates challenge packs from challenges/*.json.
--
-- The JSON Schema in challenges/schema.json is the authoritative contract and
-- is enforced in CI. The checks here are a lightweight runtime subset so a
-- broken or hand-edited pack produces a readable error instead of a crash
-- mid-game.
local check = require("vimdojo.check")
local compat = require("vimdojo.compat")
local goals = require("vimdojo.goals")

local M = {}

---@class vimdojo.Track
---@field id string
---@field title string

--- Tracks in menu order. Each track progresses independently.
---@type vimdojo.Track[]
M.TRACKS = {
  { id = "motions", title = "Motions" },
  { id = "usage", title = "Usage" },
  { id = "setup", title = "Setup" },
}
M.DEFAULT_TRACK = "motions"

local TRACK_IDS = {}
for _, track in ipairs(M.TRACKS) do
  TRACK_IDS[track.id] = true
end

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
---@field requires { nvim: string }|nil Minimum Neovim version, e.g. "0.11".
---@field options table<string, string|number|boolean>|nil Set (like :set) before the level starts.
---@field preset vimdojo.Preset|nil

---@class vimdojo.Preset
---@field registers table<string, string|string[]>|nil A string is charwise, a list of lines linewise.
---@field marks table<string, integer[]>|nil Buffer marks a-z as [line, col].

---@class vimdojo.Pack
---@field pack string
---@field title string
---@field description string|nil
---@field order integer
---@field track string One of M.TRACKS; defaults to "motions".
---@field levels vimdojo.Level[]

--- Where the packs ship with the plugin.
---
--- A git checkout (lazy.nvim, packer, vim-plug) keeps `challenges/` next to
--- `lua/`. A LuaRocks install (rocks.nvim) does not: the modules go to the
--- Lua tree while `challenges/` is copied into the rock's directory, which is
--- on 'runtimepath' alongside `plugin/vimdojo.lua`. Try both.
---@return string
function M.default_dir()
  local this_file = debug.getinfo(1, "S").source:sub(2)
  local beside_lua = vim.fn.fnamemodify(this_file, ":p:h:h:h") .. "/challenges"
  if vim.fn.isdirectory(beside_lua) == 1 then
    return beside_lua
  end
  return M.runtime_dir() or beside_lua
end

--- The `challenges/` directory of the runtimepath entry that provides
--- `plugin/vimdojo.lua`, so another plugin's `challenges/` is never picked.
---@return string|nil
function M.runtime_dir()
  for _, plugin_file in ipairs(vim.api.nvim_get_runtime_file("plugin/vimdojo.lua", true)) do
    local dir = vim.fn.fnamemodify(plugin_file, ":p:h:h") .. "/challenges"
    if vim.fn.isdirectory(dir) == 1 then
      return dir
    end
  end
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

---@param options any
---@return string|nil
local function options_error(options)
  if options == nil then
    return nil
  end
  if type(options) ~= "table" then
    return "options must be an object"
  end
  for name, value in pairs(options) do
    local known = type(name) == "string" and pcall(vim.api.nvim_get_option_info2, name, {})
    if not known then
      return ("options: unknown option %q"):format(tostring(name))
    end
    local kind = type(value)
    if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then
      return ("options.%s must be a string, number or boolean"):format(name)
    end
  end
end

---@param preset any
---@return string|nil
local function preset_error(preset)
  if preset == nil then
    return nil
  end
  if type(preset) ~= "table" then
    return "preset must be an object"
  end
  for name, value in pairs(preset.registers or {}) do
    if not tostring(name):match('^[a-z0-9"%-]$') then
      return ("preset.registers: invalid register %q"):format(tostring(name))
    end
    if type(value) ~= "string" and not check.is_string_list(value) then
      return ("preset.registers.%s must be a string or an array of lines"):format(name)
    end
  end
  for name, position in pairs(preset.marks or {}) do
    if not tostring(name):match("^[a-z]$") then
      return ("preset.marks: invalid mark %q (a-z)"):format(tostring(name))
    end
    local valid = type(position) == "table"
      and check.is_integer(position[1])
      and check.is_integer(position[2])
      and position[1] >= 1
      and position[2] >= 0
    if not valid then
      return ("preset.marks.%s must be [line, col]"):format(name)
    end
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
  expect(
    level.requires == nil
      or (type(level.requires) == "table" and compat.parse(level.requires.nvim) ~= nil),
    'requires must be { "nvim": "MAJOR.MINOR" }'
  )
  local options_err = options_error(level.options)
  expect(options_err == nil, options_err)
  local preset_err = preset_error(level.preset)
  expect(preset_err == nil, preset_err)
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
  if pack.track ~= nil and not TRACK_IDS[pack.track] then
    table.insert(
      errors,
      ("track must be one of motions, usage, setup (got %q)"):format(tostring(pack.track))
    )
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
  decoded.track = decoded.track or M.DEFAULT_TRACK
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

---@param packs vimdojo.Pack[]
---@param level_id string
---@return vimdojo.Level|nil
function M.find(packs, level_id)
  for _, pack in ipairs(packs) do
    for _, level in ipairs(pack.levels) do
      if level.id == level_id then
        return level
      end
    end
  end
end

--- The level after `level_id` in curriculum order, crossing into the next
--- pack at the end of a pack.
---@param packs vimdojo.Pack[] Sorted by order.
---@param level_id string
---@return vimdojo.Level|nil
function M.next_level(packs, level_id)
  local found = false
  for _, pack in ipairs(packs) do
    for _, level in ipairs(pack.levels) do
      if found then
        return level
      end
      found = level.id == level_id
    end
  end
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
