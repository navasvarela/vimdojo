-- Orchestrates a play session: loads data, opens the level in a clean room
-- (room.lua), counts keys, and records the outcome. Holds the only mutable
-- game state.
local challenges = require("vimdojo.challenges")
local compat = require("vimdojo.compat")
local daily = require("vimdojo.daily")
local game = require("vimdojo.game")
local goals = require("vimdojo.goals")
local keylog = require("vimdojo.keylog")
local keys = require("vimdojo.keys")
local lesson_panel = require("vimdojo.lesson_panel")
local level_hash = require("vimdojo.level_hash")
local menu = require("vimdojo.menu")
local progress = require("vimdojo.progress")
local results = require("vimdojo.results")
local room = require("vimdojo.room")
local storage = require("vimdojo.storage")
local tips = require("vimdojo.tips")
local tmaps = require("vimdojo.tmaps")
local ui = require("vimdojo.ui")

local uv = vim.uv or vim.loop

local M = {}

-- 100 ms keeps the timer readable to a tenth of a second without measurable cost.
local STATUS_REFRESH_MS = 100

---@class vimdojo.Play
---@field level vimdojo.Level
---@field daily_date string|nil Set when this is the daily challenge.
---@field practice boolean Nothing about this attempt is recorded.
---@field session vimdojo.Session
---@field layout vimdojo.Layout
---@field room vimdojo.Room
---@field ready boolean The room has loaded the level; keys count from now on.
---@field augroup integer
---@field stop_capture fun()|nil
---@field ticker uv.uv_timer_t|nil
---@field saved_mouse string|nil
---@field restore_tmaps fun()|nil

---@type { packs: vimdojo.Pack[]|nil, progress: vimdojo.Progress|nil, play: vimdojo.Play|nil, results: vimdojo.Panel|nil }
local state = { packs = nil, progress = nil, play = nil, results = nil }

---@return vimdojo.Config
local function config()
  return require("vimdojo").config
end

---@return string
local function progress_path()
  return config().progress_path or storage.default_path()
end

---@return number
local function clock()
  return uv.hrtime() / 1e9
end

---@param message string
---@param level integer|nil
local function notify(message, level)
  vim.notify("vimdojo: " .. message, level or vim.log.levels.INFO)
end

---@return boolean loaded
local function ensure_loaded()
  if state.packs then
    return true
  end
  local packs, err = challenges.load_dir(config().challenges_dir)
  if not packs then
    notify("could not load challenges:\n" .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  local data, warning = storage.load(progress_path())
  if warning then
    vim.notify(warning, vim.log.levels.WARN)
  end
  state.packs, state.progress = packs, data
  return true
end

---@type vimdojo.Supports
local function supports(level)
  return compat.supports(level, compat.running())
end

---@return table<string, true>
local function unlocked_levels()
  if config().unlock_all then
    return progress.unlocked_all(state.packs)
  end
  return progress.unlocked_by_progress(state.progress, state.packs, supports)
end

---@param play vimdojo.Play
---@return string
local function status_text(play)
  local session = play.session
  if play.practice then
    return (" practice · keys %d · par %d keys"):format(session.keys, play.level.par_keys)
  end
  local text = (" time %.1fs · keys %d · par %d keys / %gs"):format(
    session:elapsed(),
    session.keys,
    play.level.par_keys,
    play.level.par_seconds
  )
  if session.hinted then
    text = text .. " · hinted"
  end
  return text
end

--- Stops everything that listens to the player. Idempotent, and safe to call
--- from any exit path (goal reached, quit, window closed under us).
---@param play vimdojo.Play
local function release_input(play)
  pcall(vim.api.nvim_del_augroup_by_id, play.augroup)
  if play.stop_capture then
    play.stop_capture()
    play.stop_capture = nil
  end
  if play.ticker then
    play.ticker:stop()
    play.ticker:close()
    play.ticker = nil
  end
  if play.saved_mouse then
    vim.o.mouse = play.saved_mouse
    play.saved_mouse = nil
  end
  if play.restore_tmaps then
    play.restore_tmaps()
    play.restore_tmaps = nil
  end
end

local function close_results()
  if state.results then
    state.results.close()
    state.results = nil
  end
end

--- Ends the current level, if any, and closes its windows.
function M.quit()
  close_results()
  local play = state.play
  if not play then
    return
  end
  state.play = nil
  release_input(play)
  play.room:close()
  play.layout:close()
end

--- The next level the player can start right away, skipping levels this
--- Neovim cannot run.
---@param level_id string
---@return vimdojo.Level|nil
local function next_playable(level_id)
  local unlocked = unlocked_levels()
  local next_level = challenges.next_level(state.packs, level_id)
  while next_level and not supports(next_level) do
    next_level = challenges.next_level(state.packs, next_level.id)
  end
  if next_level and unlocked[next_level.id] then
    return next_level
  end
end

--- Keeps the attempt's keys if it could rank on a board: played in a stock
--- Neovim (your mappings change what keys mean), with nothing pasted, and not a
--- Setup level (their probes can be forged, PLAN-v3 L5). A level that can't be
--- hashed, which only a custom pack can have, can't rank either.
---@param play vimdojo.Play
---@param outcome vimdojo.Outcome
local function record_key_log(play, outcome)
  local log = play.session:key_log()
  if not log or config().config ~= "clean" or #goals.probes(play.level.goal) > 0 then
    return
  end
  local hashed, hash = pcall(level_hash.of, play.level)
  if not hashed then
    return
  end
  local v = vim.version()
  local ok, err = keylog.record(config().keylog_dir or keylog.default_dir(), {
    version = keylog.VERSION,
    level_id = play.level.id,
    level_hash = hash,
    nvim = ("%d.%d.%d"):format(v.major, v.minor, v.patch),
    keys = log.keys,
    deltas_ms = log.deltas_ms,
    claimed = { keys = outcome.keys, seconds = outcome.seconds, hinted = outcome.hinted },
  })
  if not ok then
    notify("could not save the key log: " .. tostring(err), vim.log.levels.WARN)
  end
end

---@param level_id string
---@return boolean
local function is_todays_daily(level_id)
  return daily.pick(daily.pool(state.packs), daily.day_number(os.time())) == level_id
end

---@return vimdojo.StreakView|nil
local function streak_view()
  local current = progress.current_streak(state.progress, daily.day_number(os.time()))
  if current > 0 then
    return { current = current, best = state.progress.daily.best }
  end
end

--- Only an attempt over par gets a tip: at or under par, there's nothing to shorten.
---@param play vimdojo.Play
---@param outcome vimdojo.Outcome
---@return string|nil
local function tip_for(play, outcome)
  local key_log = play.session:key_log()
  if key_log and outcome.keys > play.level.par_keys then
    return tips.tip(key_log.keys)
  end
end

--- Practice stays off every record: no progress, streak, key log or submission.
---@param play vimdojo.Play
local function complete_practice(play)
  local outcome = play.session:finish()
  release_input(play)
  play.layout:set_status(status_text(play))
  local level_id = play.level.id
  local key_log = play.session:key_log()
  state.results = results.open_practice({
    level = play.level,
    outcome = outcome,
    typed_keys = key_log and key_log.keys,
    solution_hidden = is_todays_daily(level_id),
    tip = tip_for(play, outcome),
  }, {
    retry = function()
      M.start_practice(level_id)
    end,
    menu = function()
      M.quit()
      M.open_menu()
    end,
    close = M.quit,
  })
end

---@param play vimdojo.Play
local function complete(play)
  local outcome = play.session:finish()
  release_input(play)
  play.layout:set_status(status_text(play))

  progress.record(state.progress, play.level.id, outcome)
  -- By level, not by how it was opened: the same level is in the menu too.
  local solved_todays_daily = is_todays_daily(play.level.id)
  if solved_todays_daily then
    progress.record_daily(state.progress, daily.day_number(os.time()))
  end
  local ok, err = storage.save(progress_path(), state.progress)
  if not ok then
    notify("could not save progress: " .. tostring(err), vim.log.levels.ERROR)
  end
  record_key_log(play, outcome)
  -- Required here, not at the top: with online features off, this file never loads.
  local online = config().online.enabled and require("vimdojo.online") or nil
  if online then
    online.on_solved(play.level.id)
  end

  local level_id = play.level.id
  local next_level = next_playable(level_id)
  local key_log = play.session:key_log()
  state.results = results.open({
    level = play.level,
    daily_date = play.daily_date,
    outcome = outcome,
    typed_keys = key_log and key_log.keys,
    solution_hidden = solved_todays_daily,
    record = state.progress.levels[level_id],
    streak = solved_todays_daily and streak_view() or nil,
    tip = tip_for(play, outcome),
    has_next = next_level ~= nil,
    has_board = online ~= nil and #goals.probes(play.level.goal) == 0,
    can_submit = online ~= nil and config().online.submit == "ask" and online.can_submit(
      play.level.id
    ),
  }, {
    submit = function()
      if online then
        online.submit(play.level.id)
      end
    end,
    board = function()
      if online then
        online.board(play.daily_date and online.DAILY_BOARD or play.level.id)
      end
    end,
    next = function()
      if next_level then
        M.start(next_level.id)
      end
    end,
    retry = function()
      M.start(level_id)
    end,
    menu = function()
      M.quit()
      M.open_menu()
    end,
    close = M.quit,
  })
end

---@param play vimdojo.Play
local function enter_room(play)
  -- nvim_open_win() fires these events while a new float still shows the room's
  -- buffer. Without the window check, a panel opened during a level (help, a
  -- board) starts in Insert mode, and its keys fail with E21 instead of working.
  if
    play.ready
    and not play.session:is_finished()
    and vim.api.nvim_get_current_win() == play.layout.room_win
  then
    vim.cmd("startinsert")
  end
end

---@param play vimdojo.Play
local function watch(play)
  vim.api.nvim_create_autocmd("WinClosed", {
    group = play.augroup,
    pattern = tostring(play.layout.room_win),
    callback = function()
      vim.schedule(M.quit)
    end,
  })
  -- Keys reach the child only in Terminal mode, so returning to the room
  -- window resumes it.
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = play.augroup,
    buffer = play.room.buf,
    callback = function()
      enter_room(play)
    end,
  })
end

---@param play vimdojo.Play
---@return vimdojo.RoomSpec
local function room_spec(play)
  return {
    level = play.level,
    keymaps = config().keymaps,
    leader = vim.g.mapleader or "\\",
  }
end

---@type table<string, fun()>
local control_actions = {
  hint = function()
    M.hint()
  end,
  reset = function()
    M.reset()
  end,
  quit = function()
    M.quit()
  end,
}

--- Control keys are counted by the key capture before the child sees them,
--- so each control takes its own keys back off the counter.
---@param play vimdojo.Play
---@param name string
local function on_control(play, name)
  local lhs = config().keymaps[name]
  local action = control_actions[name]
  if not lhs or not action then
    return
  end
  play.session:uncount_keys(keys.count(lhs))
  action()
end

---@param play vimdojo.Play
---@return vimdojo.RoomHandlers
local function room_handlers(play)
  return {
    on_ready = function(r)
      r:load(room_spec(play))
      play.ready = true
      if vim.api.nvim_get_current_win() == play.layout.room_win then
        enter_room(play)
      end
    end,
    on_solved = function()
      if state.play ~= play then
        return
      end
      if play.practice then
        complete_practice(play)
      else
        complete(play)
      end
    end,
    on_control = function(_, name)
      if state.play == play then
        on_control(play, name)
      end
    end,
    on_exit = function()
      if state.play == play and not play.session:is_finished() then
        notify("the level's Neovim exited, so the level was closed")
        M.quit()
      end
    end,
  }
end

---@param play vimdojo.Play
local function capture_input(play)
  play.saved_mouse = vim.o.mouse
  -- A click could focus away from the room mid-attempt; the child has the
  -- mouse disabled too.
  vim.o.mouse = ""
  play.restore_tmaps = tmaps.suspend()
  play.stop_capture = keys.capture(function()
    return play.ready
      and not play.session:is_finished()
      and vim.api.nvim_get_current_win() == play.layout.room_win
      and vim.api.nvim_get_mode().mode == "t"
  end, {
    on_keys = function(names)
      play.session:press(names)
    end,
    on_paste = function(count)
      play.session:paste(count)
    end,
  })
  play.ticker = uv.new_timer()
  play.ticker:start(
    0,
    STATUS_REFRESH_MS,
    vim.schedule_wrap(function()
      if state.play == play then
        play.layout:set_status(status_text(play))
      end
    end)
  )
end

---@param level vimdojo.Level
---@return boolean
local function check_supported(level)
  if supports(level) then
    return true
  end
  notify(("that level needs Neovim %s or newer"):format(level.requires.nvim), vim.log.levels.WARN)
  return false
end

---@param level vimdojo.Level
---@param mode { daily_date: string|nil, practice: boolean|nil }|nil
local function open_level(level, mode)
  M.quit()
  ui.close_panels()
  mode = mode or {}
  local play = {
    level = level,
    daily_date = mode.daily_date,
    practice = mode.practice == true,
    session = game.new(level, clock),
    layout = ui.open_level(level, { window = config().window, controls = config().keymaps }),
    ready = false,
    augroup = vim.api.nvim_create_augroup("vimdojo.play", { clear = true }),
  }
  play.room = room.open(play.layout.room_win, {
    config = config().config,
    handlers = room_handlers(play),
  })
  state.play = play
  watch(play)
  capture_input(play)
end

---@param level_id string
function M.start(level_id)
  if not ensure_loaded() then
    return
  end
  local level = challenges.find(state.packs, level_id)
  if not level then
    notify(("unknown level %q"):format(level_id), vim.log.levels.ERROR)
    return
  end
  if not check_supported(level) then
    return
  end
  if not unlocked_levels()[level_id] then
    notify("that level is still locked", vim.log.levels.WARN)
    return
  end
  open_level(level)
end

---@class vimdojo.Daily
---@field date string
---@field level vimdojo.Level

--- Today's (UTC) daily challenge, or nil when no loaded pack has demo levels
--- (a custom `challenges_dir`).
---@return vimdojo.Daily|nil
local function todays_daily()
  local day = daily.day_number(os.time())
  local level_id = daily.pick(daily.pool(state.packs), day)
  local level = level_id and challenges.find(state.packs, level_id)
  if level then
    return { date = daily.date(day), level = level }
  end
end

--- Plays today's daily challenge. Everyone gets the same level, so it
--- ignores pack locks.
function M.start_daily()
  if not ensure_loaded() then
    return
  end
  local today = todays_daily()
  if not today then
    notify("no daily challenge: none of the loaded packs has demo levels", vim.log.levels.WARN)
    return
  end
  if check_supported(today.level) then
    open_level(today.level, { daily_date = today.date })
  end
end

--- Plays a level with nothing recorded. Today's daily ignores locks here too, since it
--- can be played from the menu whatever the player has unlocked.
---@param level_id string|nil
function M.start_practice(level_id)
  if not level_id then
    notify("name a level, or press p on one in the menu")
    return
  end
  if not ensure_loaded() then
    return
  end
  local level = challenges.find(state.packs, level_id)
  if not level then
    notify(("unknown level %q"):format(level_id), vim.log.levels.ERROR)
    return
  end
  if not check_supported(level) then
    return
  end
  if not unlocked_levels()[level_id] and not is_todays_daily(level_id) then
    notify("that level is still locked", vim.log.levels.WARN)
    return
  end
  open_level(level, { practice = true })
end

--- Restarts the current level in place. A hint already seen stays counted.
function M.reset()
  local play = state.play
  if not play or play.session:is_finished() then
    return
  end
  local hinted = play.session.hinted
  play.session = game.new(play.level, clock)
  if hinted then
    play.session:use_hint()
  end
  play.room:load(room_spec(play))
  play.layout:set_status(status_text(play))
end

function M.hint()
  local play = state.play
  if not play or play.session:is_finished() or play.session.hinted then
    return
  end
  play.session:use_hint()
  play.layout:show_hint(play.level.hint)
end

--- A pack's lesson helps most before its first level, so the menu shows it until one of
--- the pack's levels is solved. The daily and practice skip it, and the menu's L key
--- shows it any time.
---@param level_id string
local function start_from_menu(level_id)
  local pack = challenges.pack_of(state.packs, level_id)
  if not (pack and pack.lesson) or progress.has_solved_any(state.progress, pack) then
    M.start(level_id)
    return
  end
  lesson_panel.open(pack.title, pack.lesson, {
    start = function()
      M.start(level_id)
    end,
    back = M.open_menu,
  })
end

function M.open_menu()
  if not ensure_loaded() then
    return
  end
  M.quit()
  ui.close_panels()
  menu.open({
    packs = state.packs,
    progress = state.progress,
    unlocked = unlocked_levels(),
    supports = supports,
    daily = todays_daily(),
    streak = streak_view(),
  }, { level = start_from_menu, daily = M.start_daily, practice = M.start_practice })
end

--- Drops cached packs and progress so the next command reloads them from disk.
function M.reload()
  M.quit()
  state.packs, state.progress = nil, nil
end

---@return vimdojo.Play|nil
function M.current()
  return state.play
end

---@return vimdojo.Progress|nil
function M.progress()
  return state.progress
end

return M
