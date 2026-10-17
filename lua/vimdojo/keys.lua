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

-- Events that arrive through the key queue but are not keys the player
-- pressed. Matched against keytrans() names such as "<LeftMouse>".
local NON_KEY_FRAGMENTS =
  { "Mouse", "ScrollWheel", "Drag", "Release", "Focus", "Ignore", "Cmd", "Paste" }

---@param name string A key in keytrans() notation.
---@return boolean
function M.is_countable(name)
  if name:sub(1, 1) ~= "<" or #name == 1 then
    return true
  end
  for _, fragment in ipairs(NON_KEY_FRAGMENTS) do
    if name:find(fragment, 1, true) then
      return false
    end
  end
  return true
end

local namespace = vim.api.nvim_create_namespace("vimdojo.keys")

--- Calls `on_keys(count)` for every physical key typed while `is_active()`
--- returns true. Only one capture can be active at a time.
---
--- `typed` (the key before mapping expansion) is what gets counted, so a
--- mapping counts as the keys the player pressed, not the keys it expands to.
---@param is_active fun(): boolean
---@param on_keys fun(count: integer)
---@return fun() stop Removes the callback.
function M.capture(is_active, on_keys)
  vim.on_key(function(_, typed)
    if typed == nil or typed == "" or not is_active() then
      return
    end
    local name = vim.fn.keytrans(typed)
    if M.is_countable(name) then
      on_keys(M.count(name))
    end
  end, namespace)
  return function()
    vim.on_key(nil, namespace)
  end
end

return M
