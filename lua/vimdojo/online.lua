-- Leaderboard accounts: `:VimDojo login`, `logout` and `account`. Off by default,
-- and nothing here runs at startup: the network is only touched when the player
-- calls one of these commands.
local challenges = require("vimdojo.challenges")
local keylog = require("vimdojo.keylog")
local scoreboard = require("vimdojo.scoreboard")
local storage = require("vimdojo.storage")
local ui = require("vimdojo.ui")

local uv = vim.uv or vim.loop

local M = {}

---@class vimdojo.OnlineConfig
---@field enabled boolean Nothing touches the network until this is true.
---@field url string The API's origin.
---@field submit "ask"|"auto"|"never" Offer `s` on the results card, submit every solve, or neither.
---@field auth_path string|nil Override for the login file (used by tests).
---@field outbox_path string|nil Override for the outbox file (used by tests).

---@class vimdojo.ApiResponse
---@field status integer HTTP status; 0 when the request never completed.
---@field body table|nil The decoded JSON body.

-- Owner read/write only. Set when the file is created, not after, so the token
-- is never briefly readable by others.
local OWNER_ONLY = tonumber("600", 8)
local REQUEST_TIMEOUT_SECONDS = 15
-- GitHub's default poll interval, used until it says otherwise.
local DEFAULT_POLL_SECONDS = 5
local ACCOUNT_URL = "https://vimdojo.org/account/"
local HTTP_OK = 200
local HTTP_NO_CONTENT = 204
local HTTP_ACCEPTED = 202
local HTTP_UNAUTHORIZED = 401
-- A run usually verifies within seconds of being sent, and otherwise within a
-- minute or two (the API's cron). This covers both, for three minutes in all.
local VERIFY_POLL_SECONDS = 3
local VERIFY_POLL_TRIES = 60
-- Setup levels are unranked until their probes can't be forged (PLAN-v3, L5).
local UNRANKED_TRACK = "setup"
-- `:VimDojo submit` stays under the API's 30 runs a minute.
local SUBMIT_ALL_GAP_SECONDS = 3

---@param message string
---@param level integer|nil
local function notify(message, level)
  vim.notify("vimdojo: " .. message, level or vim.log.levels.INFO)
end

---@return vimdojo.OnlineConfig
local function config()
  return require("vimdojo").config.online
end

---@return string
local function auth_path()
  return config().auth_path or (vim.fn.stdpath("data") .. "/vimdojo/auth.json")
end

--- The login token: the environment wins, for players using a secret manager.
---@return string|nil
function M.token()
  local from_env = vim.env.VIMDOJO_TOKEN
  if from_env and from_env ~= "" then
    return from_env
  end
  local file = io.open(auth_path(), "rb")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  local ok, data = pcall(vim.json.decode, text)
  return ok and type(data) == "table" and data.token or nil
end

--- Writes the file with its permissions set from the moment it exists, then
--- renames it over any previous one.
---@param token string
---@return boolean|nil ok
---@return string|nil err
function M.save_token(token)
  local path = auth_path()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local tmp = path .. ".tmp"
  os.remove(tmp)
  local fd, open_err = uv.fs_open(tmp, "w", OWNER_ONLY)
  if not fd then
    return nil, open_err
  end
  local _, write_err = uv.fs_write(fd, vim.json.encode({ token = token }))
  uv.fs_close(fd)
  if write_err then
    os.remove(tmp)
    return nil, write_err
  end
  local renamed, rename_err = uv.fs_rename(tmp, path)
  if not renamed then
    os.remove(tmp)
    return nil, rename_err
  end
  return true
end

function M.forget_token()
  os.remove(auth_path())
end

---@return string
local function outbox_path()
  return config().outbox_path or (vim.fn.stdpath("state") .. "/vimdojo/outbox.json")
end

---@return string
local function keylog_dir()
  return require("vimdojo").config.keylog_dir or keylog.default_dir()
end

--- Levels whose runs couldn't be sent. Only their ids: the key logs hold the runs.
---@return string[]
local function read_outbox()
  local file = io.open(outbox_path(), "rb")
  if not file then
    return {}
  end
  local text = file:read("*a")
  file:close()
  local ok, ids = pcall(vim.json.decode, text)
  return ok and type(ids) == "table" and ids or {}
end

---@param ids string[]
local function write_outbox(ids)
  if #ids == 0 then
    os.remove(outbox_path())
    return
  end
  storage.write_atomic(outbox_path(), vim.json.encode(ids))
end

---@param level_id string
local function add_to_outbox(level_id)
  local ids = read_outbox()
  if not vim.tbl_contains(ids, level_id) then
    table.insert(ids, level_id)
    write_outbox(ids)
  end
end

---@param level_id string
local function remove_from_outbox(level_id)
  write_outbox(vim.tbl_filter(function(id)
    return id ~= level_id
  end, read_outbox()))
end

--- Only a loopback address may use plain HTTP, for running the API locally.
---@param url string
---@return boolean
local function is_loopback(url)
  return url:match("^http://localhost[:/]") ~= nil or url:match("^http://127%.0%.0%.1[:/]") ~= nil
end

--- curl's arguments. The token and body go through stdin (see `curl_config`):
--- anything in argv is visible to every user on the machine in the process list.
---@param method string
---@param url string
---@return string[]
function M.curl_args(method, url)
  local args = {
    "curl",
    "--silent",
    "--show-error",
    "--max-time",
    tostring(REQUEST_TIMEOUT_SECONDS),
    "--request",
    method,
    "--write-out",
    "\\n%{http_code}",
    "--config",
    "-",
  }
  if not is_loopback(url) then
    vim.list_extend(args, { "--proto", "=https", "--tlsv1.2" })
  end
  table.insert(args, url)
  return args
end

---@param value string
---@return string
local function curl_quoted(value)
  return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

--- curl's config file format, sent on stdin.
---@param token string|nil
---@param body table|nil
---@return string
function M.curl_config(token, body)
  local lines = {}
  if token then
    table.insert(lines, "header = " .. curl_quoted("Authorization: Bearer " .. token))
  end
  if body then
    table.insert(lines, 'header = "Content-Type: application/json"')
    table.insert(lines, "data-binary = " .. curl_quoted(vim.json.encode(body)))
  end
  return table.concat(lines, "\n") .. "\n"
end

--- Splits curl's output, with the status code on the last line (`--write-out`).
---@param stdout string
---@return vimdojo.ApiResponse
function M.parse_response(stdout)
  local text, status = stdout:match("^(.*)\n(%d+)$")
  if not status then
    return { status = 0 }
  end
  local ok, body = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
  return { status = tonumber(status) or 0, body = ok and type(body) == "table" and body or nil }
end

--- The real transport. Tests replace it with `M._set_deps`.
---@param method string
---@param path string
---@param options { token: string|nil, body: table|nil }
---@param callback fun(response: vimdojo.ApiResponse)
local function curl_request(method, path, options, callback)
  local url = config().url .. path
  local spawned, process = pcall(vim.system, M.curl_args(method, url), {
    stdin = M.curl_config(options.token, options.body),
    text = true,
  }, function(result)
    vim.schedule(function()
      callback(M.parse_response(result.stdout or ""))
    end)
  end)
  if not spawned then
    callback({ status = 0 })
  end
  return process
end

---@class vimdojo.OnlineDeps
---@field request fun(method: string, path: string, options: table, callback: fun(response: vimdojo.ApiResponse))
---@field defer fun(callback: fun(), ms: integer)
---@field input fun(opts: table, callback: fun(value: string|nil))
---@field select fun(items: table, opts: table, callback: fun(item: any))

---@type vimdojo.OnlineDeps
local deps =
  { request = curl_request, defer = vim.defer_fn, input = vim.ui.input, select = vim.ui.select }

--- Lets tests stand in for the network, timers and prompts.
---@param overrides table
function M._set_deps(overrides)
  deps = vim.tbl_extend("force", deps, overrides)
end

function M._reset_deps()
  deps =
    { request = curl_request, defer = vim.defer_fn, input = vim.ui.input, select = vim.ui.select }
end

---@return boolean
local function require_enabled()
  if config().enabled then
    return true
  end
  notify("online features are off. Set `online = { enabled = true }` in setup() first.")
  return false
end

---@param response vimdojo.ApiResponse
---@return string
local function failure_message(response)
  if response.status == 0 then
    return "couldn't reach the server (is curl installed, and are you online?)"
  end
  return (response.body and response.body.message) or ("the server said %d"):format(response.status)
end

--- Asks until the handle is accepted, or the player cancels.
---@param token string
---@param on_done fun(handle: string|nil)
local function choose_handle(token, on_done)
  deps.input({ prompt = "Pick a public handle for the leaderboards: " }, function(value)
    if not value or value == "" then
      notify("no handle chosen. Run :VimDojo account to pick one later.")
      on_done(nil)
      return
    end
    deps.request("PATCH", "/api/v1/me", { token = token, body = { handle = value } }, function(res)
      if res.status == HTTP_OK then
        on_done(value)
      else
        notify(failure_message(res), vim.log.levels.WARN)
        choose_handle(token, on_done)
      end
    end)
  end)
end

---@param token string
---@param handle string|nil
local function finish_login(token, handle)
  local saved, err = M.save_token(token)
  if not saved then
    notify("couldn't save your login: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  if handle then
    notify(("signed in as %s."):format(handle))
    return
  end
  choose_handle(token, function(chosen)
    if chosen then
      notify(("signed in as %s."):format(chosen))
    end
  end)
end

-- Bumped by each login, so a poll left over from an abandoned one stops.
local login_generation = 0

---@param device_id string
---@param interval_seconds integer
---@param generation integer
local function poll(device_id, interval_seconds, generation)
  deps.defer(function()
    if generation ~= login_generation then
      return
    end
    local body = { device_id = device_id }
    deps.request("POST", "/api/v1/auth/device/poll", { body = body }, function(res)
      if generation ~= login_generation then
        return
      end
      local status = res.body and res.body.status
      if status == "ok" then
        finish_login(res.body.token, res.body.handle)
      elseif status == "pending" then
        poll(device_id, res.body.interval or interval_seconds, generation)
      elseif status == "expired" then
        notify("the login expired or was denied. Run :VimDojo login to try again.")
      elseif res.status == 0 then
        -- A dropped connection mid-login isn't fatal; GitHub's code stays valid.
        poll(device_id, interval_seconds, generation)
      else
        notify(failure_message(res), vim.log.levels.ERROR)
      end
    end)
  end, interval_seconds * 1000)
end

---@type table<string, fun(run: table): string>
local RUN_OUTCOMES = {
  verified = function(run)
    return ("verified: %d keys on %s."):format(run.verified_keys, run.level_id)
  end,
  mismatch = function(run)
    return ("verified at %d keys on %s (your game counted %d)."):format(
      run.verified_keys,
      run.level_id,
      run.claimed_keys
    )
  end,
  rejected = function(run)
    return ("%s: the replay didn't solve the level, so this run isn't ranked."):format(run.level_id)
  end,
  failed = function(run)
    return ("%s: this run couldn't be verified."):format(run.level_id)
  end,
  unranked = function(run)
    return ("%s isn't ranked, so this run stays off the boards."):format(run.level_id)
  end,
  not_best = function(run)
    return ("%s: this run doesn't beat your verified best."):format(run.level_id)
  end,
}

--- Levels that can rank, from the packs that ship with the plugin.
---@return vimdojo.ScoreLevel[]
function M.ranked_levels()
  local packs = challenges.load_dir()
  local levels = {}
  for _, pack in ipairs(packs or {}) do
    if pack.track ~= UNRANKED_TRACK then
      for _, level in ipairs(pack.levels) do
        table.insert(levels, { id = level.id, title = level.title, par_keys = level.par_keys })
      end
    end
  end
  return levels
end

---@param level_id string
---@return vimdojo.ScoreLevel|nil
local function ranked_level(level_id)
  for _, level in ipairs(M.ranked_levels()) do
    if level.id == level_id then
      return level
    end
  end
end

---@param level vimdojo.ScoreLevel
---@param entries vimdojo.BoardEntry[]
---@param mine vimdojo.OwnRank|nil
local function open_board_panel(level, entries, mine)
  ui.define_highlights()
  local rows = scoreboard.board_rows(entries, mine)
  local panel = ui.open_panel({
    title = (" %s: par %d "):format(level.title, level.par_keys),
    lines = rows.lines,
    highlights = rows.highlights,
    footer = " q close ",
  })
  ui.map(panel.buf, { q = panel.close, ["<Esc>"] = panel.close })
end

---@param level vimdojo.ScoreLevel
local function show_board(level)
  local path = ("/api/v1/levels/%s/board"):format(level.id)
  deps.request("GET", path, {}, function(res)
    if res.status ~= HTTP_OK or not res.body then
      notify(failure_message(res), vim.log.levels.WARN)
      return
    end
    local entries = res.body.entries or {}
    local token = M.token()
    if not token then
      open_board_panel(level, entries, nil)
      return
    end
    deps.request("GET", path .. "/me", { token = token }, function(own)
      open_board_panel(level, entries, own.status == HTTP_OK and own.body or nil)
    end)
  end)
end

--- `:VimDojo board [level]`: a level's board, without leaving Neovim. Boards are
--- public, so this works signed out too; signed in, it also shows your place.
---@param level_id string|nil Asks which level when left out.
function M.board(level_id)
  if not require_enabled() then
    return
  end
  if level_id then
    local level = ranked_level(level_id)
    if level then
      show_board(level)
    else
      notify(("%s has no board: it isn't a ranked level."):format(level_id), vim.log.levels.WARN)
    end
    return
  end
  deps.select(M.ranked_levels(), {
    prompt = "Which level's board?",
    format_item = function(level)
      return level.title
    end,
  }, function(level)
    if level then
      show_board(level)
    end
  end)
end

--- The keys of each level's local best run.
---@return table<string, integer>
local function local_bests()
  local bests = {}
  for _, path in ipairs(vim.fn.glob(keylog_dir() .. "/*.json", false, true)) do
    local level_id = vim.fn.fnamemodify(path, ":t:r")
    local run = keylog.load(keylog_dir(), level_id)
    if run then
      bests[level_id] = run.claimed.keys
    end
  end
  return bests
end

--- `:VimDojo scores`: your verified bests and places, and what you haven't sent.
function M.scores()
  local token = M.token()
  if not require_enabled() then
    return
  end
  if not token then
    notify("you aren't signed in. Run :VimDojo login.")
    return
  end
  deps.request("GET", "/api/v1/me/scores", { token = token }, function(res)
    if res.status == HTTP_UNAUTHORIZED then
      notify("your login has expired. Run :VimDojo login.")
      return
    end
    if res.status ~= HTTP_OK or not res.body then
      notify(failure_message(res), vim.log.levels.WARN)
      return
    end
    ui.define_highlights()
    local rows = scoreboard.score_rows(M.ranked_levels(), res.body.scores or {}, local_bests())
    local panel = ui.open_panel({
      title = " Your scores ",
      lines = rows.lines,
      highlights = rows.highlights,
      footer = rows.unsent > 0 and " <CR> board · s send all · q close "
        or " <CR> board · q close ",
    })
    ui.map(panel.buf, {
      ["<CR>"] = function()
        local level_id = rows.level_at[vim.api.nvim_win_get_cursor(panel.win)[1]]
        if level_id then
          M.board(level_id)
        end
      end,
      s = function()
        panel.close()
        M.submit_all()
      end,
      q = panel.close,
      ["<Esc>"] = panel.close,
    })
  end)
end

--- Adds the player's place to a verdict, so the good news doesn't need a second step.
---@param token string
---@param level_id string
---@param message string
local function notify_with_rank(token, level_id, message)
  deps.request(
    "GET",
    ("/api/v1/levels/%s/board/me"):format(level_id),
    { token = token },
    function(res)
      local rank = res.status == HTTP_OK and res.body and res.body.rank
      if rank then
        notify(("%s You're #%d: :VimDojo board %s"):format(message, rank, level_id))
      else
        notify(message)
      end
    end
  )
end

--- Waits for the verdict, without holding anything up: a player can keep playing.
---@param token string
---@param run_id string
---@param level_id string
---@param tries_left integer
local function await_verdict(token, run_id, level_id, tries_left)
  if tries_left == 0 then
    notify(
      ("%s is taking longer than usual to verify. It's safe: run :VimDojo scores later."):format(
        level_id
      )
    )
    return
  end
  deps.defer(function()
    deps.request("GET", "/api/v1/runs/" .. run_id, { token = token }, function(res)
      local outcome = res.body and RUN_OUTCOMES[res.body.status]
      if outcome and res.body.verified_keys then
        notify_with_rank(token, level_id, outcome(res.body))
      elseif outcome then
        notify(outcome(res.body))
      else
        await_verdict(token, run_id, level_id, tries_left - 1)
      end
    end)
  end, VERIFY_POLL_SECONDS * 1000)
end

--- Sends a level's best run. Without a connection it waits in the outbox; a refusal
--- is final, because trying the same run again wouldn't change the answer.
---@param level_id string
---@param token string
---@param quiet boolean Don't wait for or report the verdict (when sending many).
local function send_run(level_id, token, quiet)
  local run = keylog.load(keylog_dir(), level_id)
  if not run then
    remove_from_outbox(level_id)
    return
  end
  deps.request("POST", "/api/v1/runs", { token = token, body = run }, function(res)
    if res.status == 0 then
      add_to_outbox(level_id)
      notify(("%s: couldn't reach the server, so it'll be sent next time."):format(level_id))
      return
    end
    if res.status == HTTP_UNAUTHORIZED then
      notify("your login has expired. Run :VimDojo login.", vim.log.levels.WARN)
      return
    end
    remove_from_outbox(level_id)
    if res.status ~= HTTP_OK and res.status ~= HTTP_ACCEPTED then
      notify(("%s: %s"):format(level_id, failure_message(res)), vim.log.levels.WARN)
      return
    end
    if quiet then
      return
    end
    if res.body.status == "pending" then
      notify(("%s submitted. Verifying: the result will show here in a moment."):format(level_id))
      await_verdict(token, res.body.id, level_id, VERIFY_POLL_TRIES)
    else
      local outcome = RUN_OUTCOMES[res.body.status]
      notify(
        outcome and outcome(vim.tbl_extend("force", run, res.body, { level_id = level_id }))
          or "submitted."
      )
    end
  end)
end

--- Sends anything a dropped connection left behind.
---@param token string
local function flush_outbox(token)
  for _, level_id in ipairs(read_outbox()) do
    send_run(level_id, token, true)
  end
end

--- Whether the results card should offer to submit this level's run.
---@param level_id string
---@return boolean
function M.can_submit(level_id)
  local online = config()
  return online.enabled
    and online.submit ~= "never"
    and M.token() ~= nil
    and keylog.load(keylog_dir(), level_id) ~= nil
end

--- Submits a level's best run, with the verdict reported when it's ready.
---@param level_id string
function M.submit(level_id)
  local token = M.token()
  if not require_enabled() then
    return
  end
  if not token then
    notify("you aren't signed in. Run :VimDojo login.")
    return
  end
  flush_outbox(token)
  send_run(level_id, token, false)
end

--- A solved level, with `submit = "auto"`: only then does finishing a level use the
--- network, and only for a player who asked for that and is signed in.
---@param level_id string
function M.on_solved(level_id)
  if config().submit == "auto" and M.can_submit(level_id) then
    M.submit(level_id)
  end
end

--- `:VimDojo submit`: sends the best run of every level played. The server treats
--- the same keys as the same run, so this is safe to repeat.
function M.submit_all()
  local token = M.token()
  if not require_enabled() then
    return
  end
  if not token then
    notify("you aren't signed in. Run :VimDojo login.")
    return
  end
  local level_ids = {}
  for _, name in ipairs(vim.fn.glob(keylog_dir() .. "/*.json", false, true)) do
    table.insert(level_ids, vim.fn.fnamemodify(name, ":t:r"))
  end
  if #level_ids == 0 then
    notify("there are no runs to submit yet. Solve a level first.")
    return
  end
  notify(("submitting %d runs…"):format(#level_ids))
  local function send_next(index)
    send_run(level_ids[index], token, true)
    if index < #level_ids then
      deps.defer(function()
        send_next(index + 1)
      end, SUBMIT_ALL_GAP_SECONDS * 1000)
    else
      notify("all sent. Verifying them can take a few minutes.")
    end
  end
  send_next(1)
end

function M.login()
  if not require_enabled() then
    return
  end
  login_generation = login_generation + 1
  local generation = login_generation
  deps.request("POST", "/api/v1/auth/device", {}, function(res)
    if res.status ~= HTTP_OK or not res.body then
      notify(failure_message(res), vim.log.levels.ERROR)
      return
    end
    notify(("open %s and enter the code %s"):format(res.body.verification_uri, res.body.user_code))
    poll(res.body.device_id, res.body.interval or DEFAULT_POLL_SECONDS, generation)
  end)
end

--- Revokes the login on the server, then forgets it here either way: a player
--- who signs out offline still expects this machine to be signed out.
function M.logout()
  if not require_enabled() then
    return
  end
  login_generation = login_generation + 1
  local token = M.token()
  if not token then
    notify("you aren't signed in.")
    return
  end
  deps.request("POST", "/api/v1/auth/logout", { token = token }, function(res)
    M.forget_token()
    if res.status == HTTP_NO_CONTENT or res.status == HTTP_UNAUTHORIZED then
      notify("signed out.")
    else
      notify("signed out here, but couldn't revoke the login: " .. failure_message(res))
    end
  end)
end

function M.account()
  if not require_enabled() then
    return
  end
  local token = M.token()
  if not token then
    notify("you aren't signed in. Run :VimDojo login.")
    return
  end
  flush_outbox(token)
  deps.request("GET", "/api/v1/me", { token = token }, function(res)
    if res.status == HTTP_UNAUTHORIZED then
      notify("your login has expired. Run :VimDojo login.")
    elseif res.status ~= HTTP_OK or not res.body then
      notify(failure_message(res), vim.log.levels.ERROR)
    elseif res.body.handle then
      notify(("signed in as %s. Manage your account at %s"):format(res.body.handle, ACCOUNT_URL))
    else
      choose_handle(token, function(chosen)
        if chosen then
          notify(("signed in as %s."):format(chosen))
        end
      end)
    end
  end)
end

return M
