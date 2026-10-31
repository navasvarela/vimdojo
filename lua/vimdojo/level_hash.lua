-- A level's identity on the leaderboards: SHA-256 over a canonical JSON
-- encoding of the fields that define play. Editing a title, hint or par keeps
-- the hash, so boards survive copy edits; changing what a player can do or must
-- reach starts a new board. web/src/level-hash.ts implements the same encoding
-- and tests/fixtures/level_hash.json pins both.
local M = {}

local ESCAPES = {
  ['"'] = '\\"',
  ["\\"] = "\\\\",
  ["\b"] = "\\b",
  ["\f"] = "\\f",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
}

--- JSON.stringify's rules: only quotes, backslashes and control characters
--- are escaped, so DEL and non-ASCII text stay as they are. `%c` would also
--- match DEL, hence the explicit range.
---@param text string
---@return string
local function encode_string(text)
  local escaped = text:gsub('[%z\1-\31"\\]', function(char)
    return ESCAPES[char] or ("\\u%04x"):format(char:byte())
  end)
  return '"' .. escaped .. '"'
end

--- Byte order, not `<`: on a PUC Lua build `<` follows the locale, and the
--- hash must be the same on every machine.
---@param a string
---@param b string
---@return boolean
local function bytes_less(a, b)
  for i = 1, math.min(#a, #b) do
    local x, y = a:byte(i), b:byte(i)
    if x ~= y then
      return x < y
    end
  end
  return #a < #b
end

---@param value any
---@return string
local function encode(value)
  local kind = type(value)
  if kind == "string" then
    return encode_string(value)
  elseif kind == "boolean" then
    return tostring(value)
  elseif kind == "number" then
    -- Formatting fractions the same way in Lua and JavaScript is hard, and no
    -- field that defines play needs them, so they are refused.
    assert(value == math.floor(value), "level hash: non-integer number")
    return ("%d"):format(value)
  end
  assert(kind == "table", "level hash: unsupported value of type " .. kind)
  if getmetatable(value) == getmetatable(vim.empty_dict()) then
    return "{}"
  end
  if vim.islist(value) then
    return "[" .. table.concat(vim.tbl_map(encode, value), ",") .. "]"
  end
  local names = vim.tbl_keys(value)
  table.sort(names, bytes_less)
  local members = vim.tbl_map(function(name)
    return encode_string(name) .. ":" .. encode(value[name])
  end, names)
  return "{" .. table.concat(members, ",") .. "}"
end

--- A workspace level's `start_text` is derived from its open file, so it is
--- only part of a level's identity when there are no files.
---@param level vimdojo.Level
---@return string
function M.canonical(level)
  return encode({
    cursor_start = level.cursor_start,
    files = level.files,
    goal = level.goal,
    open = level.files and level.open or nil,
    options = level.options,
    preset = level.preset,
    requires = level.requires,
    start_text = (not level.files) and level.start_text or nil,
  })
end

---@param level vimdojo.Level
---@return string hash "sha256:<hex>"
function M.of(level)
  return "sha256:" .. vim.fn.sha256(M.canonical(level))
end

return M
