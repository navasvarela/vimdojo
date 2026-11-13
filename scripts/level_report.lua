-- The level report on pull requests: what a PR does to the levels, for a reviewer.
-- For every level it adds, changes or removes it lists whether the level's board
-- starts over, its par beside the reference solution and (for cursor_at levels) the
-- par search, and whether it runs code on players' machines.
--
--   nvim --headless --noplugin -u NONE -l scripts/level_report.lua BASE_DIR OUT_DIR
--
-- BASE_DIR holds the base branch's challenges/. OUT_DIR gets report.md and
-- needs-code-review ("true" or "false"), which .github/workflows/level-report.yml
-- turns into a comment and a label. Prints nothing and writes an empty report when
-- no level changed.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.o.swapfile = false

local challenges = require("vimdojo.challenges")
local keys = require("vimdojo.keys")
local level_hash = require("vimdojo.level_hash")
local par_search = dofile(root .. "/scripts/par_search.lua")

local SETUP_TRACK = "setup"

---@param base_dir string
---@return table<string, vimdojo.Level>
local function base_levels(base_dir)
  -- A base without packs (or one this code can't read) makes every level new, which
  -- over-reports rather than hides a change.
  local packs = challenges.load_dir(base_dir) or {}
  local levels = {}
  for _, pack in ipairs(packs) do
    for _, level in ipairs(pack.levels) do
      levels[level.id] = level
    end
  end
  return levels
end

---@param goal vimdojo.Goal
---@return boolean
local function has_lua_probe(goal)
  if goal.type == "all_of" then
    for _, inner in ipairs(goal.goals) do
      if has_lua_probe(inner) then
        return true
      end
    end
  end
  for _, probe in ipairs(goal.type == "config_probes" and goal.probes or {}) do
    if probe.kind == "lua" then
      return true
    end
  end
  return false
end

--- What in a level runs code on players' machines (see .github/CODEOWNERS).
---@param pack vimdojo.Pack
---@param level vimdojo.Level
---@return string[]
local function code_fields(pack, level)
  local fields = {}
  if level.preset and level.preset.commands then
    table.insert(fields, "`preset.commands`")
  end
  if has_lua_probe(level.goal) then
    table.insert(fields, "a `lua` probe")
  end
  if pack.track == SETUP_TRACK then
    table.insert(fields, "a Setup starter config")
  end
  return fields
end

---@class vimdojo.ReportRow
---@field pack vimdojo.Pack
---@field level vimdojo.Level
---@field change string

---@param old vimdojo.Level|nil
---@param new vimdojo.Level
---@return string|nil change Nil when the level didn't change.
local function change_of(old, new)
  if old == nil then
    return "new"
  end
  if level_hash.of(old) ~= level_hash.of(new) then
    return "changed: **its board starts over**"
  end
  if vim.inspect(old) ~= vim.inspect(new) then
    return "changed (same board)"
  end
end

---@param text string
---@return string
local function code(text)
  return "`" .. text:gsub("`", "'"):gsub("|", "\\|") .. "`"
end

---@param row vimdojo.ReportRow
---@param found vimdojo.ParOptimum|nil
---@return string
local function row_text(row, found)
  local level = row.level
  local notes = {}
  local solution_keys = keys.count(level.solution)
  if solution_keys > level.par_keys then
    table.insert(notes, ("⚠️ the solution takes %d keys, over par"):format(solution_keys))
  end
  local search = "by hand"
  if found then
    search = ("taught %s %s · any %s %s"):format(
      tostring(found.taught_cost),
      found.taught_path and code(found.taught_path) or "",
      tostring(found.any_cost),
      found.any_path and code(found.any_path) or ""
    )
    if found.expected ~= level.par_keys then
      table.insert(notes, ("⚠️ par should be %s"):format(tostring(found.expected)))
    end
  end
  local runs = code_fields(row.pack, level)
  if #runs > 0 then
    table.insert(notes, "🔒 runs code: " .. table.concat(runs, ", "))
  end
  return ("| %s | %s | %d | %s | %s | %s |"):format(
    code(level.id),
    row.change,
    level.par_keys,
    code(level.solution),
    search,
    table.concat(notes, "<br>")
  )
end

---@param base_dir string
---@return string report
---@return boolean needs_code_review
local function build(base_dir)
  local before = base_levels(base_dir)
  local packs = assert(challenges.load_dir(root .. "/challenges"))
  local rows, changed_ids, seen = {}, {}, {}
  local needs_code_review = false
  for _, pack in ipairs(packs) do
    for _, level in ipairs(pack.levels) do
      seen[level.id] = true
      local change = change_of(before[level.id], level)
      if change then
        table.insert(rows, { pack = pack, level = level, change = change })
        changed_ids[level.id] = true
        needs_code_review = needs_code_review or #code_fields(pack, level) > 0
      end
    end
  end
  local removed = {}
  for id in pairs(before) do
    if not seen[id] then
      table.insert(removed, code(id))
    end
  end
  table.sort(removed)
  if #rows == 0 and #removed == 0 then
    return "", false
  end

  local optima = par_search.optima(packs, changed_ids)
  local lines = {
    "## Levels in this pull request",
    "",
    "| Level | Change | Par | Reference solution | Par search | Notes |",
    "|---|---|---|---|---|---|",
  }
  for _, row in ipairs(rows) do
    table.insert(lines, row_text(row, optima[row.level.id]))
  end
  if #removed > 0 then
    table.insert(lines, "")
    table.insert(lines, "**Removed, with their boards:** " .. table.concat(removed, ", "))
  end
  vim.list_extend(lines, {
    "",
    "The par search only covers `cursor_at` levels; work out the par of a text goal by hand"
      .. " (see the par rule in `docs/authoring-levels.md`). It shows the shortest route with"
      .. " the motions taught so far and with any motion; a daily's par is the second.",
  })
  if needs_code_review then
    vim.list_extend(lines, {
      "",
      "🔒 **Runs code on players' machines.** A maintainer reads these fields before merging,"
        .. " not only the green checks.",
    })
  end
  return table.concat(lines, "\n") .. "\n", needs_code_review
end

local base_dir, out_dir = arg[1], arg[2]
assert(base_dir and out_dir, "usage: level_report.lua BASE_DIR OUT_DIR")
local report, needs_code_review = build(base_dir)
vim.fn.mkdir(out_dir, "p")
vim.fn.writefile(vim.split(report, "\n", { plain = true }), out_dir .. "/report.md")
vim.fn.writefile({ tostring(needs_code_review) }, out_dir .. "/needs-code-review")
io.stdout:write(report)
