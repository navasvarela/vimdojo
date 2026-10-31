-- One attempt at a level, as a small state machine:
--
--   ready --(first key)--> playing --(goal met)--> finished
--
-- Pure: time comes from an injected clock, so tests can drive it.
local scoring = require("vimdojo.scoring")

local M = {}

M.State = { Ready = "ready", Playing = "playing", Finished = "finished" }

-- Results are stored with centisecond precision so progress.json stays tidy
-- and the Lua and web scores agree on the same rounded input.
local SECONDS_PRECISION = 100
local MS_PER_SECOND = 1000

---@class vimdojo.Outcome
---@field keys integer
---@field seconds number
---@field hinted boolean
---@field stars integer
---@field points integer

---@class vimdojo.Session
---@field level vimdojo.Level
---@field state string One of M.State.
---@field keys integer
---@field hinted boolean
---@field started_at number|nil Clock reading at the first counted key.
---@field outcome vimdojo.Outcome|nil Set once finished.
---@field key_names string[] The counted keys, in order.
---@field key_times number[] Clock reading of each entry in key_names.
---@field pasted boolean Text was pasted, so key_names doesn't hold every key.
---@field private clock fun(): number Monotonic seconds.
local Session = {}
Session.__index = Session

---@param level vimdojo.Level
---@param clock fun(): number Monotonic time in seconds.
---@return vimdojo.Session
function M.new(level, clock)
  return setmetatable({
    level = level,
    state = M.State.Ready,
    keys = 0,
    hinted = false,
    started_at = nil,
    outcome = nil,
    key_names = {},
    key_times = {},
    pasted = false,
    clock = clock,
  }, Session)
end

---@return boolean
function Session:is_finished()
  return self.state == M.State.Finished
end

---@return boolean
function Session:is_playing()
  return self.state == M.State.Playing
end

--- The timer starts on the first key, not when the level opens.
---@param count integer
function Session:count_keys(count)
  if self:is_finished() then
    return
  end
  if self.state == M.State.Ready then
    self.state = M.State.Playing
    self.started_at = self.clock()
  end
  self.keys = self.keys + count
end

--- Counts typed keys and keeps them for the key log.
---@param names string[] One entry per physical key.
function Session:press(names)
  if self:is_finished() then
    return
  end
  self:count_keys(#names)
  local now = self.clock()
  for _, name in ipairs(names) do
    table.insert(self.key_names, name)
    table.insert(self.key_times, now)
  end
end

--- Counts pasted text. Its keys can't be logged: a paste isn't the same as
--- typing the text, so a replay of it wouldn't reproduce the attempt.
---@param count integer
function Session:paste(count)
  self.pasted = self.pasted or not self:is_finished()
  self:count_keys(count)
end

--- Takes back keys that turned out to be game controls (hint, reset). If that
--- leaves no keys, the attempt has not really started, so the timer resets.
--- The controls are the latest keys: the room reports one the moment it fires,
--- far quicker than the next key can be typed.
---@param count integer
function Session:uncount_keys(count)
  if self:is_finished() then
    return
  end
  self.keys = math.max(0, self.keys - count)
  for _ = 1, math.min(count, #self.key_names) do
    table.remove(self.key_names)
    table.remove(self.key_times)
  end
  if self.keys == 0 then
    self.state = M.State.Ready
    self.started_at = nil
  end
end

function Session:use_hint()
  self.hinted = true
end

---@return number
function Session:elapsed()
  if self.outcome then
    return self.outcome.seconds
  end
  if not self.started_at then
    return 0
  end
  return self.clock() - self.started_at
end

--- The attempt's keys and the gaps between them. Each gap comes from rounded
--- absolute times, so rounding errors can't add up: the gaps sum to the time from
--- the first key to the last, to the millisecond.
---@return vimdojo.KeyLog|nil log Nil when text was pasted.
function Session:key_log()
  if self.pasted then
    return nil
  end
  local deltas = {}
  local previous = nil
  for _, time in ipairs(self.key_times) do
    local ms = math.floor(time * MS_PER_SECOND + 0.5)
    table.insert(deltas, previous and ms - previous or 0)
    previous = ms
  end
  return { keys = vim.list_extend({}, self.key_names), deltas_ms = deltas }
end

---@return vimdojo.Outcome
function Session:finish()
  if self.outcome then
    return self.outcome
  end
  local seconds = math.floor(self:elapsed() * SECONDS_PRECISION + 0.5) / SECONDS_PRECISION
  local score = scoring.score({
    keys = self.keys,
    seconds = seconds,
    par_keys = self.level.par_keys,
    par_seconds = self.level.par_seconds,
    hinted = self.hinted,
  })
  self.outcome = {
    keys = self.keys,
    seconds = seconds,
    hinted = self.hinted,
    stars = score.stars,
    points = score.points,
  }
  self.state = M.State.Finished
  return self.outcome
end

return M
