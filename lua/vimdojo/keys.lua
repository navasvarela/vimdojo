local M = {}

local SPECIAL_KEY = "^<[%w%-]+>"
-- A modifier with a punctuation key, which the pattern above can't match:
-- <C-^>, <C-]>, <M-.>.
local MODIFIED_PUNCTUATION = "^<%a%-[^%w>]>"
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
    local key = notation:match(SPECIAL_KEY, pos)
      or notation:match(MODIFIED_PUNCTUATION, pos)
      or notation:match(UTF8_CHAR, pos)
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

--- The keys a paste would have cost if typed: one per character, plus one
--- `<CR>` per line break. `lines` is one chunk as `vim.paste` receives it;
--- a streamed paste splits a line across chunks, so summing chunks still
--- counts each line break once.
---@param lines string[]
---@return integer
function M.paste_count(lines)
  local count = math.max(#lines - 1, 0)
  for _, line in ipairs(lines) do
    count = count + vim.fn.strchars(line)
  end
  return count
end

local namespace = vim.api.nvim_create_namespace("vimdojo.keys")

---@class vimdojo.KeyHandlers
---@field on_keys fun(names: string[]) Keys typed, one entry per physical key.
---@field on_paste fun(count: integer) Pasted text, as the keys it would cost.

--- Reports every physical key typed and every paste while `is_active()` returns
--- true. Only one capture can be active at a time.
---
--- `typed` (the key before mapping expansion) is what gets counted, so a
--- mapping counts as the keys the player pressed, not the keys it expands to.
---
--- Pasted text costs what typing it would. A paste (bracketed paste in a
--- terminal, or a GUI's) reaches `vim.paste` without ever passing through
--- `vim.on_key` (measured in terminal mode on 0.12), so it is counted there.
---@param is_active fun(): boolean
---@param handlers vimdojo.KeyHandlers
---@return fun() stop Removes the callbacks.
function M.capture(is_active, handlers)
  vim.on_key(function(_, typed)
    if typed == nil or typed == "" or not is_active() then
      return
    end
    local name = vim.fn.keytrans(typed)
    if M.is_countable(name) then
      handlers.on_keys(M.split(name))
    end
  end, namespace)

  local original_paste = vim.paste
  local function counting_paste(lines, phase)
    if is_active() then
      handlers.on_paste(M.paste_count(lines))
    end
    return original_paste(lines, phase)
  end
  vim.paste = counting_paste

  return function()
    vim.on_key(nil, namespace)
    -- Leave a handler that someone installed after us in place.
    if vim.paste == counting_paste then
      vim.paste = original_paste
    end
  end
end

return M
