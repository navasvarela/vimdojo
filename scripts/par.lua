-- Par finder for cursor_at levels: searches for the shortest key sequence that
-- reaches each level's goal, using real Neovim motions.
--
--   nvim --headless --noplugin -u NONE -l scripts/par.lua
--
-- For every cursor_at level it reports two optima:
--   taught: using only motions taught so far in the curriculum (the par rule)
--   any:    using every motion in the catalogue below
--
-- This is an authoring aid, not a test: the search state is just the cursor
-- position, so it ignores 'curswant' (the column j/k try to return to) and
-- the last f/t target (so ; and , are not searched). Treat results as strong
-- hints and confirm surprising ones by hand.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.o.swapfile = false

local challenges = require("vimdojo.challenges")
local keys = require("vimdojo.keys")

local SIMPLE_MOTIONS = {
  "h",
  "j",
  "k",
  "l",
  "w",
  "b",
  "e",
  "W",
  "B",
  "E",
  "0",
  "^",
  "$",
  "gg",
  "G",
  "{",
  "}",
  "%",
  "*",
  "#",
}
local FIND_MOTIONS = { "f", "t", "F", "T" }
local COUNTABLE = {
  h = true,
  j = true,
  k = true,
  l = true,
  w = true,
  b = true,
  e = true,
  W = true,
  B = true,
  E = true,
  ["{"] = true,
  ["}"] = true,
}
local MAX_COUNT = 9
-- Search patterns tried: every substring of the buffer up to this length.
-- Longer patterns are rarely the shortest route, and the search space grows
-- with every extra character.
local MAX_PATTERN = 4
-- Characters with a special meaning in a search pattern; substrings
-- containing them are skipped rather than escaped.
local PATTERN_SPECIALS = "[%.%*%[%]%^%$\\/~?]"

---@param lines string[]
---@return string[]
local function distinct_chars(lines)
  local seen, chars = {}, {}
  for _, line in ipairs(lines) do
    for char in line:gmatch(".") do
      if not seen[char] then
        seen[char] = true
        table.insert(chars, char)
      end
    end
  end
  return chars
end

---@param lines string[]
---@return string[] Distinct buffer substrings usable as plain search patterns.
local function search_patterns(lines)
  local seen, patterns = {}, {}
  for _, line in ipairs(lines) do
    for start = 1, #line do
      for length = 1, MAX_PATTERN do
        local pattern = line:sub(start, start + length - 1)
        if #pattern == length and not pattern:find(PATTERN_SPECIALS) and not seen[pattern] then
          seen[pattern] = true
          table.insert(patterns, pattern)
        end
      end
    end
  end
  return patterns
end

---@param allowed fun(motion: string): boolean
---@param lines string[]
---@return string[]
local function alphabet(allowed, lines)
  local tokens = {}
  for _, motion in ipairs(SIMPLE_MOTIONS) do
    if allowed(motion) then
      table.insert(tokens, motion)
      if COUNTABLE[motion] and allowed("count") then
        for count = 2, MAX_COUNT do
          table.insert(tokens, count .. motion)
        end
      end
    end
  end
  if allowed("count") then
    -- j/k counts beyond 9 matter in long levels (logs, configs).
    for _, motion in ipairs({ "j", "k" }) do
      if allowed(motion) then
        for count = MAX_COUNT + 1, #lines do
          table.insert(tokens, count .. motion)
        end
      end
    end
    if allowed("G") then
      for line = 1, #lines do
        table.insert(tokens, line .. "G")
      end
    end
  end
  for _, search in ipairs({ "/", "?" }) do
    if allowed(search) then
      for _, pattern in ipairs(search_patterns(lines)) do
        table.insert(tokens, search .. pattern .. "<CR>")
      end
    end
  end
  for _, motion in ipairs(FIND_MOTIONS) do
    if allowed(motion) then
      for _, char in ipairs(distinct_chars(lines)) do
        table.insert(tokens, motion .. char)
      end
    end
  end
  return tokens
end

---@param position integer[]
---@param token string
---@return integer[]
local function move(position, token)
  vim.api.nvim_win_set_cursor(0, position)
  -- silent!: failed or wrapping searches would print messages (and errors).
  vim.cmd("silent! normal! " .. vim.api.nvim_replace_termcodes(token, true, false, true))
  return vim.api.nvim_win_get_cursor(0)
end

--- Dijkstra over cursor positions; edge cost is the token's key count.
---@param level vimdojo.Level
---@param tokens string[]
---@return integer|nil cost
---@return string|nil path
local function shortest(level, tokens)
  local goal = level.goal.line .. ":" .. level.goal.col
  local function id(pos)
    return pos[1] .. ":" .. pos[2]
  end
  local best = { [id(level.cursor_start)] = 0 }
  local frontier = { { cost = 0, pos = level.cursor_start, path = "" } }
  while #frontier > 0 do
    table.sort(frontier, function(a, b)
      return a.cost > b.cost
    end)
    local node = table.remove(frontier)
    if id(node.pos) == goal then
      return node.cost, node.path
    end
    if node.cost <= best[id(node.pos)] then
      for _, token in ipairs(tokens) do
        local next_pos = move(node.pos, token)
        local cost = node.cost + keys.count(token)
        local key = id(next_pos)
        if best[key] == nil or cost < best[key] then
          best[key] = cost
          table.insert(frontier, { cost = cost, pos = next_pos, path = node.path .. token })
        end
      end
    end
  end
end

local packs = assert(challenges.load_dir())
local taught = {}
vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(false, true))
for _, pack in ipairs(packs) do
  for _, level in ipairs(pack.levels) do
    for _, key in ipairs(level.teaches) do
      taught[key] = true
    end
    if level.goal.type == "cursor_at" then
      vim.api.nvim_buf_set_lines(0, 0, -1, false, level.start_text)
      local basics = { h = true, j = true, k = true, l = true }
      local taught_cost, taught_path = shortest(
        level,
        alphabet(function(m)
          return basics[m] or taught[m]
        end, level.start_text)
      )
      local any_cost, any_path = shortest(
        level,
        alphabet(function()
          return true
        end, level.start_text)
      )
      local flag = (taught_cost ~= level.par_keys) and "  <-- par mismatch" or ""
      print(
        ("%-18s par %2d | taught %2s %-10s | any %2s %-8s%s"):format(
          level.id,
          level.par_keys,
          tostring(taught_cost),
          taught_path or "-",
          tostring(any_cost),
          any_path or "-",
          flag
        )
      )
    end
  end
end
