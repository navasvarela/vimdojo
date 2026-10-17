-- Window and buffer plumbing: scratch buffers, floating panels, and the level
-- layout (a header with the brief plus the window that hosts the clean room).
local goal_views = require("vimdojo.goal_views")

local M = {}

M.namespace = vim.api.nvim_create_namespace("vimdojo.ui")

local HIGHLIGHTS = {
  VimDojoTitle = { link = "Title" },
  VimDojoMuted = { link = "Comment" },
  VimDojoStar = { link = "DiagnosticWarn" },
  VimDojoLocked = { link = "NonText" },
  VimDojoGood = { link = "DiagnosticOk" },
}

function M.define_highlights()
  for name, spec in pairs(HIGHLIGHTS) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", spec, { default = true }))
  end
end

---@param count integer
---@return string
function M.stars(count)
  return string.rep("★", count) .. string.rep("☆", 3 - count)
end

---@param text string
---@param width integer Display width to pad to.
---@return string
function M.pad(text, width)
  return text .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(text)))
end

--- Replaces the buffer text without leaving an undo step, so `u` cannot undo
--- a level back to an empty buffer.
---@param buf integer
---@param lines string[]
function M.replace_text(buf, lines)
  local bo = vim.bo[buf]
  local undolevels = bo.undolevels
  bo.modifiable = true
  bo.undolevels = -1
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  bo.undolevels = undolevels
end

---@param lines string[]
---@return integer buf
function M.scratch_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  M.replace_text(buf, lines)
  return buf
end

---@class vimdojo.Highlight
---@field line integer 0-based.
---@field col integer 0-based byte column.
---@field end_col integer|nil Defaults to the end of the line.
---@field group string

---@param buf integer
---@param highlights vimdojo.Highlight[]
function M.apply_highlights(buf, highlights)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(buf, M.namespace, hl.line, hl.col, {
      end_row = hl.end_col and hl.line or hl.line + 1,
      end_col = hl.end_col or 0,
      hl_group = hl.group,
      strict = false,
    })
  end
end

---@param lines string[]
---@return integer
local function max_width(lines)
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  return width
end

---@param lines string[]
---@param width integer
---@return integer Rows the lines occupy when wrapped at `width`.
local function wrapped_height(lines, width)
  local rows = 0
  for _, line in ipairs(lines) do
    rows = rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
  end
  return rows
end

---@class vimdojo.PanelSpec
---@field title string
---@field lines string[]
---@field highlights vimdojo.Highlight[]|nil
---@field footer string|nil

---@class vimdojo.Panel
---@field buf integer
---@field win integer
---@field close fun()

--- A centered, read-only floating panel that takes focus (menus, results).
---@param spec vimdojo.PanelSpec
---@return vimdojo.Panel
function M.open_panel(spec)
  local buf = M.scratch_buf(spec.lines)
  M.apply_highlights(buf, spec.highlights or {})
  vim.bo[buf].modifiable = false

  local width = math.min(max_width(spec.lines) + 2, vim.o.columns - 4)
  local height = math.min(#spec.lines, vim.o.lines - 4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = "rounded",
    title = spec.title,
    title_pos = "center",
    footer = spec.footer,
    footer_pos = spec.footer and "center" or nil,
    zindex = 60,
  })
  vim.wo[win].cursorline = true

  return {
    buf = buf,
    win = win,
    close = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  }
end

---@param buf integer
---@param mappings table<string, fun()> lhs -> handler, Normal mode.
function M.map(buf, mappings)
  for lhs, handler in pairs(mappings) do
    vim.keymap.set("n", lhs, handler, { buffer = buf, nowait = true, silent = true })
  end
end

---@class vimdojo.LevelSizes
---@field width integer
---@field header_height integer
---@field room_height integer

---@class vimdojo.Layout
---@field room_win integer Hosts the clean room's terminal buffer.
---@field header_buf integer
---@field header_win integer
---@field hint_line integer 0-based header line reserved for the hint.
local Layout = {}

local HINT_PREFIX = "Hint: "
Layout.__index = Layout

---@param text string
function Layout:set_status(text)
  if vim.api.nvim_win_is_valid(self.room_win) then
    vim.wo[self.room_win].winbar = text:gsub("%%", "%%%%")
  end
end

--- Fills the header's reserved hint line. The header was sized for the hint
--- up front, so the layout never has to move.
---@param hint string
function Layout:show_hint(hint)
  if not vim.api.nvim_buf_is_valid(self.header_buf) then
    return
  end
  vim.bo[self.header_buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.header_buf, self.hint_line, self.hint_line + 1, false, {
    HINT_PREFIX .. hint,
  })
  vim.bo[self.header_buf].modifiable = false
end

function Layout:close()
  for _, win in ipairs({ self.header_win, self.room_win }) do
    if vim.api.nvim_win_is_valid(win) then
      -- Fails only when this is the last window of the last tab; the room is
      -- stopped and the game is over, so leaving it open is harmless.
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end

--- The child Neovim draws its own line numbers and cursor; the parent's
--- window decorations would only steal columns from it.
---@param win integer
local function style_room_window(win)
  local wo = vim.wo[win]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.cursorline = false
  wo.spell = false
  wo.list = false
  wo.colorcolumn = ""
  wo.scrolloff = 0
  wo.sidescrolloff = 0
end

---@param win integer
local function style_header_window(win)
  local wo = vim.wo[win]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.wrap = true
  wo.linebreak = true
  wo.cursorline = false
  wo.winfixheight = true
end

-- Where a level is played; selected by the `window` option.
---@type table<string, fun(room_buf: integer, header_buf: integer, sizes: vimdojo.LevelSizes, title: string): integer, integer>
local placements = {
  float = function(room_buf, header_buf, sizes, title)
    local total_height = sizes.header_height + sizes.room_height + 4
    local row = math.max(0, math.floor((vim.o.lines - total_height) / 2) - 1)
    local col = math.max(0, math.floor((vim.o.columns - sizes.width - 2) / 2))
    local header_win = vim.api.nvim_open_win(header_buf, false, {
      relative = "editor",
      row = row,
      col = col,
      width = sizes.width,
      height = sizes.header_height,
      style = "minimal",
      border = "rounded",
      title = " " .. title .. " ",
      title_pos = "center",
      focusable = false,
      zindex = 50,
    })
    local room_win = vim.api.nvim_open_win(room_buf, true, {
      relative = "editor",
      row = row + sizes.header_height + 2,
      col = col,
      width = sizes.width,
      height = sizes.room_height,
      border = "rounded",
      zindex = 50,
    })
    return room_win, header_win
  end,

  tab = function(room_buf, header_buf, sizes)
    vim.cmd("tabnew")
    local placeholder = vim.api.nvim_get_current_buf()
    local room_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(room_win, room_buf)
    if vim.api.nvim_buf_is_valid(placeholder) then
      vim.api.nvim_buf_delete(placeholder, { force = true })
    end
    vim.cmd(("aboveleft %dsplit"):format(sizes.header_height))
    local header_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(header_win, header_buf)
    vim.api.nvim_set_current_win(room_win)
    return room_win, header_win
  end,
}

---@class vimdojo.Header
---@field lines string[]
---@field highlights vimdojo.Highlight[]
---@field hint_line integer 0-based line that show_hint() replaces.
---@field revealed_hint string The hint line once shown, used for sizing.

---@param level vimdojo.Level
---@param controls vimdojo.Controls
---@return vimdojo.Header
local function header_content(level, controls)
  local lines = { level.description, "" }
  vim.list_extend(lines, goal_views.describe(level.goal))
  table.insert(lines, "")
  table.insert(lines, ("Par: %d keys · %gs"):format(level.par_keys, level.par_seconds))
  table.insert(
    lines,
    ("%s%s shows it (caps the attempt at 2 stars)"):format(HINT_PREFIX, controls.hint)
  )
  table.insert(lines, ("%s reset · %s quit"):format(controls.reset, controls.quit))
  local last = #lines - 1
  return {
    lines = lines,
    highlights = {
      { line = last - 2, col = 0, group = "VimDojoGood" },
      { line = last - 1, col = 0, group = "VimDojoMuted" },
      { line = last, col = 0, group = "VimDojoMuted" },
    },
    hint_line = last - 1,
    revealed_hint = HINT_PREFIX .. level.hint,
  }
end

---@param level vimdojo.Level
---@param header vimdojo.Header
---@return vimdojo.LevelSizes
local function level_sizes(level, header)
  local content = vim.list_extend(vim.deepcopy(level.start_text), level.goal.value or {})
  local number_column = 6
  local width = math.max(max_width(content) + number_column + 2, 60)
  width = math.min(width, vim.o.columns - 6)
  local header_height = wrapped_height(header.lines, width)
    + math.max(
      0,
      wrapped_height({ header.revealed_hint }, width)
        - wrapped_height({ header.lines[header.hint_line + 1] }, width)
    )
  -- The text, plus the parent's winbar and the child's command line.
  local room_height = math.max(#level.start_text + 2, 4)
  room_height = math.min(room_height, math.max(4, vim.o.lines - header_height - 8))
  return { width = width, header_height = header_height, room_height = room_height }
end

---@class vimdojo.Controls
---@field hint string
---@field reset string
---@field quit string

---@class vimdojo.LevelLayoutOptions
---@field window "float"|"tab"
---@field controls vimdojo.Controls

---@param level vimdojo.Level
---@param opts vimdojo.LevelLayoutOptions
---@return vimdojo.Layout
function M.open_level(level, opts)
  M.define_highlights()
  local header = header_content(level, opts.controls)
  local header_buf = M.scratch_buf(header.lines)
  M.apply_highlights(header_buf, header.highlights)
  vim.bo[header_buf].modifiable = false

  -- Placeholder until the room replaces it with its terminal buffer.
  local room_buf = M.scratch_buf({})

  local place = placements[opts.window] or placements.float
  local room_win, header_win = place(room_buf, header_buf, level_sizes(level, header), level.title)
  style_room_window(room_win)
  style_header_window(header_win)

  return setmetatable({
    room_win = room_win,
    header_buf = header_buf,
    header_win = header_win,
    hint_line = header.hint_line,
  }, Layout)
end

return M
