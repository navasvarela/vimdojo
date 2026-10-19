-- The clean room: every level runs in a child Neovim inside a terminal window.
-- The player's keys go to the child (and are counted by the parent with
-- vim.on_key); the child reports readiness, solved goals and control keys
-- back over RPC. Registers, options, mappings and plugins of the player's own
-- session are never touched by a level, and every level runs against the
-- same stock defaults its reference solution was tested with.
--
--   parent (this file)                       child (room/child.lua)
--   open(): :terminal nvim --clean ... ----> start(): connect to parent,
--                                              name the channel, notify "ready"
--   _event("ready") <------------------------
--   room:load(spec) ------------------------> load(): buffer, cursor, mappings
--   _event("control", name) <---------------- control key mapping
--   _event("solved") <----------------------- goal met in Normal mode
local M = {}

---@class vimdojo.RoomHandlers
---@field on_ready fun(room: vimdojo.Room)
---@field on_solved fun(room: vimdojo.Room)
---@field on_control fun(room: vimdojo.Room, name: string)
---@field on_exit fun(room: vimdojo.Room)

---@class vimdojo.RoomOptions
---@field config "clean"|"mine" Start the child with --clean, or with the player's config.
---@field handlers vimdojo.RoomHandlers

---@class vimdojo.Room
---@field id string
---@field buf integer The terminal buffer.
---@field job integer
---@field chan integer|nil RPC channel to the child, set once it is ready.
---@field closing boolean
---@field handlers vimdojo.RoomHandlers
local Room = {}
Room.__index = Room

---@type table<string, vimdojo.Room>
local rooms = {}
local next_id = 0

-- Stop every room when Neovim exits. On Windows a terminal job's process can
-- outlive the Neovim that started it, which would leave an orphaned room.
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("vimdojo.rooms", { clear = true }),
  callback = function()
    for _, room in pairs(rooms) do
      room:close()
    end
  end,
})

-- The child is started without this plugin on its runtimepath (--clean), so
-- it gets the directory holding the `vimdojo` modules through the
-- environment. Works for git checkouts (lua/) and LuaRocks trees alike.
local LUA_DIR = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

local BOOTSTRAP = table.concat({
  "lua package.path = vim.env.VIMDOJO_LUA_DIR .. '/?.lua;'",
  ".. vim.env.VIMDOJO_LUA_DIR .. '/?/init.lua;' .. package.path;",
  "require('vimdojo.room.child').start()",
}, " ")

---@param config "clean"|"mine"
---@return string[]
local function child_command(config)
  local cmd = { vim.v.progpath }
  if config ~= "mine" then
    table.insert(cmd, "--clean")
  end
  -- No swap or shada: a level must leave no trace in the player's state.
  vim.list_extend(cmd, { "-n", "-i", "NONE", "--cmd", "set shortmess+=I", "-c", BOOTSTRAP })
  return cmd
end

---@return string
local function server_address()
  if vim.v.servername == "" then
    vim.fn.serverstart()
  end
  return vim.v.servername
end

---@param cmd string[]
---@param opts table jobstart options
---@return integer job
local function open_terminal(cmd, opts)
  if vim.fn.has("nvim-0.11") == 1 then
    return vim.fn.jobstart(cmd, vim.tbl_extend("force", opts, { term = true }))
  end
  return vim.fn.termopen(cmd, opts)
end

---@param room_id string
---@return integer|nil
local function find_channel(room_id)
  local name = "vimdojo-room-" .. room_id
  for _, chan in ipairs(vim.api.nvim_list_chans()) do
    if chan.client and chan.client.name == name then
      return chan.id
    end
  end
end

--- Starts a child Neovim in a new terminal buffer shown in `win`.
---@param win integer
---@param opts vimdojo.RoomOptions
---@return vimdojo.Room
function M.open(win, opts)
  next_id = next_id + 1
  local id = tostring(next_id)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, buf)

  local room = setmetatable({
    id = id,
    buf = buf,
    job = -1,
    chan = nil,
    closing = false,
    handlers = opts.handlers,
  }, Room)
  rooms[id] = room

  vim.api.nvim_win_call(win, function()
    room.job = open_terminal(child_command(opts.config), {
      env = {
        VIMDOJO_PARENT = server_address(),
        VIMDOJO_ROOM = id,
        VIMDOJO_LUA_DIR = LUA_DIR,
      },
      on_exit = function()
        vim.schedule(function()
          room:_exited()
        end)
      end,
    })
  end)
  vim.bo[buf].bufhidden = "wipe"
  return room
end

---@return boolean
function Room:is_ready()
  return self.chan ~= nil
end

--- Calls a function of room/child.lua in the child and returns its result.
---@param fn string
---@return any result
function Room:call(fn, ...)
  if not self.chan then
    error("vimdojo: the room is not ready yet")
  end
  return vim.rpcrequest(
    self.chan,
    "nvim_exec_lua",
    ("return require('vimdojo.room.child').%s(...)"):format(fn),
    { ... }
  )
end

---@param spec vimdojo.RoomSpec
function Room:load(spec)
  self:call("load", spec)
end

---@return vimdojo.Snapshot|nil
function Room:snapshot()
  local snapshot = self:call("snapshot")
  if snapshot == vim.NIL then
    return nil
  end
  return snapshot
end

--- Stops the child. Safe to call more than once.
function Room:close()
  self.closing = true
  rooms[self.id] = nil
  pcall(vim.fn.jobstop, self.job)
end

function Room:_exited()
  rooms[self.id] = nil
  if not self.closing then
    self.closing = true
    self.handlers.on_exit(self)
  end
end

---@type table<string, fun(room: vimdojo.Room, payload: any)>
local event_handlers = {
  ready = function(room)
    room.chan = find_channel(room.id)
    room.handlers.on_ready(room)
  end,
  solved = function(room)
    room.handlers.on_solved(room)
  end,
  control = function(room, name)
    room.handlers.on_control(room, name)
  end,
}

--- Called by the child through `nvim_exec_lua` notifications. Handlers run on
--- the next tick so they may call back into the child safely.
---@param room_id string
---@param event string
---@param payload any
function M._event(room_id, event, payload)
  local room, handle = rooms[room_id], event_handlers[event]
  if room and handle then
    vim.schedule(function()
      if not room.closing then
        handle(room, payload)
      end
    end)
  end
end

return M
