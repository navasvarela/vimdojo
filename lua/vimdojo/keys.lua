local M = {}

local SPECIAL_KEY = "^<[%w%-]+>"
-- One UTF-8 encoded character: a lead byte followed by its continuation bytes.
local UTF8_CHAR = "^[%z\1-\127\194-\244][\128-\191]*"

--- Splits a key-notation string ("d2w", "ciwfoo<Esc>") into one entry per
--- physical key, so "<Esc>" and "<C-r>" count as a single key each.
---@param notation string
---@return string[]
function M.split(notation)
  local result = {}
  local pos = 1
  while pos <= #notation do
    local key = notation:match(SPECIAL_KEY, pos) or notation:match(UTF8_CHAR, pos)
    -- An invalid UTF-8 byte matches neither pattern; count it as one key
    -- rather than looping forever.
    key = key or notation:sub(pos, pos)
    table.insert(result, key)
    pos = pos + #key
  end
  return result
end

---@param notation string
---@return integer
function M.count(notation)
  return #M.split(notation)
end

return M
