-- Reads and writes progress.json. Tolerates a missing or corrupt file: a
-- corrupt one is moved aside (never deleted) and play continues from scratch.
local check = require("vimdojo.check")
local progress = require("vimdojo.progress")

local uv = vim.uv or vim.loop

local M = {}

---@return string
function M.default_path()
  return vim.fn.stdpath("data") .. "/vimdojo/progress.json"
end

---@param record any
---@return boolean
local function is_record(record)
  return type(record) == "table"
    and check.is_integer(record.best_keys)
    and type(record.best_seconds) == "number"
    and check.is_integer(record.stars)
    and check.is_integer(record.attempts)
end

---@param data any
---@return string|nil err
local function shape_error(data)
  if type(data) ~= "table" or type(data.levels) ~= "table" then
    return "expected an object with a levels table"
  end
  if data.version ~= progress.VERSION then
    return ("unsupported version %s"):format(tostring(data.version))
  end
  for id, record in pairs(data.levels) do
    if type(id) ~= "string" or not is_record(record) then
      return ("malformed record for level %s"):format(tostring(id))
    end
  end
end

---@param text string
---@return vimdojo.Progress|nil data
---@return string|nil err
local function decode(text)
  local ok, data = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
  if not ok then
    return nil, "invalid JSON"
  end
  local err = shape_error(data)
  if err then
    return nil, err
  end
  return data
end

---@param path string
---@return string backup_path
local function backup_corrupt(path)
  local backup = ("%s.corrupt-%d"):format(path, os.time())
  uv.fs_rename(path, backup)
  return backup
end

---@param path string
---@return vimdojo.Progress data Always usable; empty when nothing valid was found.
---@return string|nil warning Set when an unreadable file was moved aside.
function M.load(path)
  local file = io.open(path, "rb")
  if not file then
    return progress.empty()
  end
  local text = file:read("*a")
  file:close()

  local data, err = decode(text)
  if data then
    return data
  end
  local backup = backup_corrupt(path)
  return progress.empty(),
    ("vimdojo: progress file was unreadable (%s); moved to %s"):format(err, backup)
end

---@param data vimdojo.Progress
---@return string
local function encode(data)
  -- An empty Lua table encodes as a JSON array; levels must stay an object.
  local levels = next(data.levels) and data.levels or vim.empty_dict()
  return vim.json.encode({ version = data.version, levels = levels })
end

--- Writes atomically: the data goes to a temporary file that is then renamed
--- over the real one, so a crash mid-write never leaves a truncated file.
---@param path string
---@param data vimdojo.Progress
---@return boolean|nil ok
---@return string|nil err
function M.save(path, data)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local tmp = path .. ".tmp"
  local file, open_err = io.open(tmp, "wb")
  if not file then
    return nil, open_err
  end
  local _, write_err = file:write(encode(data))
  file:close()
  if write_err then
    os.remove(tmp)
    return nil, write_err
  end
  local ok, rename_err = uv.fs_rename(tmp, path)
  if not ok then
    os.remove(tmp)
    return nil, rename_err
  end
  return true
end

return M
