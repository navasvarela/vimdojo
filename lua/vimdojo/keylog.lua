-- Keeps each level's best rankable run on this machine: the keys and their
-- timing, which a server can replay to verify the score. Never sent anywhere by
-- this module. It lives apart from progress.json on purpose: that file is
-- exportable and shareable, and a key log is the level's solution.
local storage = require("vimdojo.storage")

local M = {}

M.VERSION = 1

---@class vimdojo.KeyLog
---@field keys string[] One entry per counted key, in Vim notation.
---@field deltas_ms integer[] Milliseconds since the previous key; the first is 0.

---@class vimdojo.Run : vimdojo.KeyLog
---@field version integer
---@field level_id string
---@field level_hash string
---@field nvim string
---@field claimed { keys: integer, seconds: number, hinted: boolean }

---@return string
function M.default_dir()
  return vim.fn.stdpath("state") .. "/vimdojo/keylogs"
end

--- Level ids become file names. Shipped ones are kebab-case; an id from a custom
--- pack that isn't safe as a file name has no board to rank on anyway.
---@param dir string
---@param level_id string
---@return string|nil
local function path_for(dir, level_id)
  if level_id:match("^[%w_%-]+$") then
    return ("%s/%s.json"):format(dir, level_id)
  end
end

---@param dir string
---@param level_id string
---@return vimdojo.Run|nil run Nil when there is none, or it is unreadable.
function M.load(dir, level_id)
  local path = path_for(dir, level_id)
  local file = path and io.open(path, "rb")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  local ok, run = pcall(vim.json.decode, text)
  if ok and type(run) == "table" and run.version == M.VERSION then
    return run
  end
end

--- A run on the level's current version always beats one on an older version,
--- whose board no longer exists. Otherwise fewer keys wins, and a tie keeps the
--- earlier run, because the first to reach a count ranks ahead on a board.
---@param previous vimdojo.Run|nil
---@param run vimdojo.Run
---@return boolean
local function improves(previous, run)
  return previous == nil
    or previous.level_hash ~= run.level_hash
    or run.claimed.keys < previous.claimed.keys
end

--- Saves `run` if it is the level's best so far.
---@param dir string
---@param run vimdojo.Run
---@return boolean|nil ok
---@return string|nil err
function M.record(dir, run)
  local path = path_for(dir, run.level_id)
  if not path or not improves(M.load(dir, run.level_id), run) then
    return true
  end
  return storage.write_atomic(path, vim.json.encode(run))
end

return M
