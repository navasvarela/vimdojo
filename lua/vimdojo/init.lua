local M = {}

---@class vimdojo.Config
---@field unlock_all boolean Unlock every pack and level regardless of progress.
---@field window "float"|"tab" Where a level is played.
---@field config "clean"|"mine" Run levels in a stock Neovim (`--clean`), or with your own config.
---@field progress_path string|nil Override for the progress file location (used by tests).
---@field keylog_dir string|nil Override for where key logs are kept (used by tests).
---@field challenges_dir string|nil Load packs from this directory instead of the built-in ones (for authors and tests).
---@field keymaps vimdojo.Controls Normal-mode game controls in the level buffer. Never counted as keystrokes.
---@field online vimdojo.OnlineConfig Leaderboard accounts. Off until you turn them on.

---@type vimdojo.Config
local defaults = {
  unlock_all = false,
  window = "float",
  config = "clean",
  progress_path = nil,
  keylog_dir = nil,
  challenges_dir = nil,
  keymaps = {
    hint = "<leader>h",
    reset = "<leader>r",
    quit = "<Esc><Esc>",
  },
  online = {
    enabled = false,
    url = "https://api.vimdojo.org",
    submit = "ask",
    auth_path = nil,
    outbox_path = nil,
  },
}

---@type vimdojo.Config
M.config = vim.deepcopy(defaults)

---@param opts vimdojo.Config|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

---@type table<string, fun(arg: string|nil)>
local subcommands = {
  menu = function()
    require("vimdojo.app").open_menu()
  end,
  daily = function()
    require("vimdojo.app").start_daily()
  end,
  reset = function()
    require("vimdojo.app").reset()
  end,
  hint = function()
    require("vimdojo.app").hint()
  end,
  quit = function()
    require("vimdojo.app").quit()
  end,
  login = function()
    require("vimdojo.online").login()
  end,
  logout = function()
    require("vimdojo.online").logout()
  end,
  account = function()
    require("vimdojo.online").account()
  end,
  submit = function()
    require("vimdojo.online").submit_all()
  end,
  board = function(level_id)
    require("vimdojo.online").board(level_id)
  end,
  scores = function()
    require("vimdojo.online").scores()
  end,
}

---@return string[]
function M.subcommands()
  local names = vim.tbl_keys(subcommands)
  table.sort(names)
  return names
end

--- Subcommands, and level ids after `board`. Levels only load if `board` was typed.
---@param arg_lead string
---@param cmd_line string
---@return string[]
function M.complete(arg_lead, cmd_line)
  local candidates = M.subcommands()
  if cmd_line:match("^%S+%s+board%s") then
    candidates = vim.tbl_map(function(level)
      return level.id
    end, require("vimdojo.online").ranked_levels())
  end
  return vim.tbl_filter(function(candidate)
    return vim.startswith(candidate, arg_lead)
  end, candidates)
end

--- `:VimDojo [subcommand]`. With no argument it opens the menu.
---@param args string[]
function M.command(args)
  local name = args[1] or "menu"
  local run = subcommands[name]
  if not run then
    vim.notify(("vimdojo: unknown subcommand %q"):format(name), vim.log.levels.ERROR)
    return
  end
  run(args[2])
end

return M
