local helpers = require("helpers")
local keylog = require("vimdojo.keylog")
local online = require("vimdojo.online")
local results = require("vimdojo.results")
local vimdojo = require("vimdojo")

local TOKEN = "vdj_secret-token-value"

describe("online", function()
  local requests, responses, timers, messages, inputs, original_notify

  --- Answers each request with the next queued response.
  local function answer(method, path, options, callback)
    table.insert(requests, { method = method, path = path, options = options })
    callback(table.remove(responses, 1) or { status = 0 })
  end

  --- Runs queued timers until none are left.
  local function run_timers()
    while #timers > 0 do
      table.remove(timers, 1)()
    end
  end

  before_each(function()
    requests, responses, timers, messages, inputs = {}, {}, {}, {}, {}
    vimdojo.setup({
      keylog_dir = helpers.temp_dir(),
      online = {
        enabled = true,
        auth_path = helpers.temp_dir() .. "/auth.json",
        outbox_path = helpers.temp_dir() .. "/outbox.json",
      },
    })
    original_notify = vim.notify
    vim.notify = function(message)
      table.insert(messages, message)
    end
    vim.env.VIMDOJO_TOKEN = nil
    online._set_deps({
      request = answer,
      defer = function(callback)
        table.insert(timers, callback)
      end,
      input = function(_, callback)
        callback(table.remove(inputs, 1))
      end,
    })
  end)

  after_each(function()
    vim.notify = original_notify
    online._reset_deps()
    vimdojo.setup({})
    vim.env.VIMDOJO_TOKEN = nil
  end)

  local function last_message()
    return messages[#messages]
  end

  describe("when off, as it is by default", function()
    it("is off by default", function()
      vimdojo.setup({})
      assert.is_false(vimdojo.config.online.enabled)
    end)

    for _, command in ipairs({ "login", "logout", "account" }) do
      it(command .. " touches no network", function()
        vimdojo.setup({})
        online[command]()
        assert.are.same({}, requests)
        assert.is_truthy(last_message():find("online features are off", 1, true))
      end)
    end
  end)

  describe("login", function()
    local device = {
      status = 200,
      body = {
        device_id = "d1",
        user_code = "ABCD-1234",
        verification_uri = "https://github.com/login/device",
        interval = 5,
      },
    }

    it("shows the code, polls, and saves the token", function()
      responses = {
        device,
        { status = 200, body = { status = "pending" } },
        { status = 200, body = { status = "ok", token = TOKEN, handle = "ana" } },
      }
      online.login()
      assert.is_truthy(last_message():find("ABCD-1234", 1, true))
      assert.is_nil(online.token())
      run_timers()
      assert.are.equal(TOKEN, online.token())
      assert.is_truthy(last_message():find("signed in as ana", 1, true))
      assert.are.same({ device_id = "d1" }, requests[2].options.body)
    end)

    it("asks for a handle at first login, and again until one is accepted", function()
      inputs = { "No Spaces", "ana" }
      responses = {
        device,
        { status = 200, body = { status = "ok", token = TOKEN } },
        { status = 422, body = { message = "Use 3 to 20 characters" } },
        { status = 200, body = { handle = "ana" } },
      }
      online.login()
      run_timers()
      assert.is_truthy(table.concat(messages, "\n"):find("Use 3 to 20", 1, true))
      assert.is_truthy(last_message():find("signed in as ana", 1, true))
      assert.are.equal(TOKEN, requests[4].options.token)
    end)

    it("keeps the login when the player skips picking a handle", function()
      inputs = {}
      responses = { device, { status = 200, body = { status = "ok", token = TOKEN } } }
      online.login()
      run_timers()
      assert.are.equal(TOKEN, online.token())
      assert.is_truthy(last_message():find(":VimDojo account", 1, true))
    end)

    it("reports an expired or denied login, and saves nothing", function()
      responses = { device, { status = 200, body = { status = "expired" } } }
      online.login()
      run_timers()
      assert.is_nil(online.token())
      assert.is_truthy(last_message():find("expired or was denied", 1, true))
    end)

    it("keeps polling through a dropped connection", function()
      responses = {
        device,
        { status = 0 },
        { status = 200, body = { status = "ok", token = TOKEN, handle = "ana" } },
      }
      online.login()
      run_timers()
      assert.are.equal(TOKEN, online.token())
    end)

    it("reports when the server can't be reached", function()
      online.login()
      assert.is_truthy(last_message():find("couldn't reach", 1, true))
    end)

    it("stops polling an abandoned login when a new one starts", function()
      responses = { device }
      online.login()
      local abandoned = timers[1]
      timers = {}
      responses = { device }
      online.login()
      local count = #requests
      abandoned()
      assert.are.equal(count, #requests)
    end)
  end)

  describe("the saved token", function()
    it("is readable only by its owner, from the moment it exists", function()
      assert.is_true(online.save_token(TOKEN))
      local mode = (vim.uv or vim.loop).fs_stat(vimdojo.config.online.auth_path).mode
      if vim.fn.has("win32") == 0 then
        -- The permission bits are the mode's low 9 bits (octal 1000 = 512).
        assert.are.equal(tonumber("600", 8), mode % 512)
      end
    end)

    it("prefers the environment variable", function()
      online.save_token(TOKEN)
      vim.env.VIMDOJO_TOKEN = "vdj_from-env"
      assert.are.equal("vdj_from-env", online.token())
    end)

    it("treats a corrupt file as signed out", function()
      vim.fn.writefile({ "not json" }, vimdojo.config.online.auth_path)
      assert.is_nil(online.token())
    end)
  end)

  describe("logout", function()
    it("revokes on the server and forgets the token", function()
      online.save_token(TOKEN)
      responses = { { status = 204 } }
      online.logout()
      assert.are.equal("/api/v1/auth/logout", requests[1].path)
      assert.are.equal(TOKEN, requests[1].options.token)
      assert.is_nil(online.token())
    end)

    it("still signs out here when offline, and says so", function()
      online.save_token(TOKEN)
      online.logout()
      assert.is_nil(online.token())
      assert.is_truthy(last_message():find("couldn't revoke", 1, true))
    end)
  end)

  describe("account", function()
    it("needs a login", function()
      online.account()
      assert.are.same({}, requests)
      assert.is_truthy(last_message():find(":VimDojo login", 1, true))
    end)

    it("shows the handle", function()
      online.save_token(TOKEN)
      responses = { { status = 200, body = { handle = "ana" } } }
      online.account()
      assert.is_truthy(last_message():find("signed in as ana", 1, true))
    end)

    it("says when the login has expired", function()
      online.save_token(TOKEN)
      responses = { { status = 401 } }
      online.account()
      assert.is_truthy(last_message():find("expired", 1, true))
    end)
  end)

  describe("submitting a run", function()
    local LEVEL = "basic-motions-01"

    local function save_run(level_id)
      assert.is_true(keylog.record(vimdojo.config.keylog_dir, {
        version = keylog.VERSION,
        level_id = level_id or LEVEL,
        level_hash = "sha256:h",
        nvim = "0.12.6",
        keys = { "j" },
        deltas_ms = { 0 },
        claimed = { keys = 1, seconds = 0.5, hinted = false },
      }))
    end

    local function outbox()
      local path = vimdojo.config.online.outbox_path
      return vim.fn.filereadable(path) == 1 and vim.json.decode(vim.fn.readfile(path)[1]) or {}
    end

    before_each(function()
      online.save_token(TOKEN)
    end)

    it("sends the best run, then reports the verdict", function()
      save_run()
      responses = {
        { status = 202, body = { id = "r1", status = "pending" } },
        { status = 200, body = { status = "pending" } },
        {
          status = 200,
          body = { status = "verified", verified_keys = 1, claimed_keys = 1, level_id = LEVEL },
        },
      }
      online.submit(LEVEL)
      assert.are.equal("/api/v1/runs", requests[1].path)
      assert.are.equal(TOKEN, requests[1].options.token)
      assert.are.same({ "j" }, requests[1].options.body.keys)
      assert.is_truthy(last_message():find("Verifying", 1, true))
      run_timers()
      assert.are.equal("/api/v1/runs/r1", requests[3].path)
      assert.is_truthy(last_message():find("verified: 1 keys", 1, true))
    end)

    local outcomes = {
      {
        { status = "mismatch", verified_keys = 5, claimed_keys = 1, level_id = LEVEL },
        "verified at 5 keys",
      },
      { { status = "rejected", level_id = LEVEL }, "didn't solve" },
      { { status = "failed", level_id = LEVEL }, "couldn't be verified" },
    }
    for _, case in ipairs(outcomes) do
      local body, expected = case[1], case[2]
      it("reports " .. body.status, function()
        save_run()
        responses = {
          { status = 202, body = { id = "r1", status = "pending" } },
          { status = 200, body = body },
        }
        online.submit(LEVEL)
        run_timers()
        assert.is_truthy(last_message():find(expected, 1, true), last_message())
      end)
    end

    it("says when a run doesn't beat the player's best, without waiting", function()
      save_run()
      responses = { { status = 200, body = { id = "r1", status = "not_best" } } }
      online.submit(LEVEL)
      assert.are.same({}, timers)
      assert.is_truthy(last_message():find("doesn't beat", 1, true))
    end)

    it("stops waiting eventually, and says how to check", function()
      save_run()
      responses = { { status = 202, body = { id = "r1", status = "pending" } } }
      for _ = 1, 30 do
        table.insert(responses, { status = 200, body = { status = "pending" } })
      end
      online.submit(LEVEL)
      run_timers()
      assert.is_truthy(last_message():find("still being verified", 1, true))
    end)

    it("keeps a run in the outbox when offline, and sends it next time", function()
      save_run()
      online.submit(LEVEL)
      assert.are.same({ LEVEL }, outbox())
      assert.is_truthy(last_message():find("next time", 1, true))

      requests = {}
      responses = {
        { status = 202, body = { id = "r1", status = "pending" } },
        { status = 200, body = { handle = "ana" } },
      }
      online.account()
      assert.are.equal("/api/v1/runs", requests[1].path)
      assert.are.same({}, outbox())
    end)

    it("doesn't retry a refusal, because the answer wouldn't change", function()
      save_run()
      responses = { { status = 409, body = { message = "That level has changed." } } }
      online.submit(LEVEL)
      assert.are.same({}, outbox())
      assert.is_truthy(last_message():find("has changed", 1, true))
    end)

    it("keeps the run through an expired login, and says to sign in", function()
      save_run()
      responses = { { status = 401 } }
      online.submit(LEVEL)
      assert.is_truthy(last_message():find(":VimDojo login", 1, true))
    end)

    it("needs a login", function()
      online.forget_token()
      save_run()
      online.submit(LEVEL)
      assert.are.same({}, requests)
    end)

    it("touches no network when off", function()
      vimdojo.config.online.enabled = false
      save_run()
      online.submit(LEVEL)
      online.submit_all()
      online.on_solved(LEVEL)
      assert.are.same({}, requests)
    end)

    it("sends every played level with :VimDojo submit, spaced out", function()
      save_run("level-a")
      save_run("level-b")
      for _ = 1, 2 do
        table.insert(responses, { status = 202, body = { id = "r", status = "pending" } })
      end
      online.submit_all()
      assert.are.equal(1, #requests)
      run_timers()
      assert.are.equal(2, #requests)
      assert.is_truthy(last_message():find("all sent", 1, true))
    end)

    it("says when there's nothing to submit", function()
      online.submit_all()
      assert.are.same({}, requests)
      assert.is_truthy(last_message():find("no runs", 1, true))
    end)

    describe("when a level is solved", function()
      local function solved_with(mode)
        vimdojo.config.online.submit = mode
        save_run()
        responses = { { status = 200, body = { id = "r1", status = "not_best" } } }
        online.on_solved(LEVEL)
      end

      it("sends nothing with submit = ask", function()
        solved_with("ask")
        assert.are.same({}, requests)
      end)

      it("sends nothing with submit = never", function()
        solved_with("never")
        assert.are.same({}, requests)
      end)

      it("sends the run with submit = auto", function()
        solved_with("auto")
        assert.are.equal("/api/v1/runs", requests[1].path)
      end)

      it("sends nothing when signed out, even with submit = auto", function()
        online.forget_token()
        solved_with("auto")
        assert.are.same({}, requests)
      end)
    end)

    describe("the results card", function()
      local function card(can_submit)
        local lines = results.content({
          level = { par_keys = 5, par_seconds = 8 },
          outcome = { keys = 5, seconds = 1, stars = 3, points = 1000 },
          record = { best_keys = 5, best_seconds = 1, stars = 3 },
          has_next = true,
          can_submit = can_submit,
        })
        return table.concat(lines, "\n")
      end

      it("offers to submit only when it can", function()
        assert.is_truthy(card(true):find("[s] submit", 1, true))
        assert.is_nil(card(false):find("submit", 1, true))
      end)

      it("can submit only when on, signed in, and with a run to send", function()
        assert.is_false(online.can_submit(LEVEL))
        save_run()
        assert.is_true(online.can_submit(LEVEL))
        vimdojo.config.online.submit = "never"
        assert.is_false(online.can_submit(LEVEL))
      end)
    end)
  end)

  describe("the curl call", function()
    it("never puts the token or body on the command line", function()
      local args = online.curl_args("PATCH", "https://api.vimdojo.org/api/v1/me")
      assert.is_nil(table.concat(args, " "):find(TOKEN, 1, true))
      local config = online.curl_config(TOKEN, { handle = "ana" })
      assert.is_truthy(config:find(TOKEN, 1, true))
      assert.is_truthy(config:find("Content-Type: application/json", 1, true))
    end)

    it("insists on HTTPS, except for a local server", function()
      local https = table.concat(online.curl_args("GET", "https://api.vimdojo.org/x"), " ")
      assert.is_truthy(https:find("--proto =https --tlsv1.2", 1, true))
      local tricky = table.concat(online.curl_args("GET", "http://localhost.evil.test/x"), " ")
      assert.is_truthy(tricky:find("--proto =https", 1, true))
      local at_sign = table.concat(online.curl_args("GET", "http://127.0.0.1.evil.test/x"), " ")
      assert.is_truthy(at_sign:find("--proto =https", 1, true))
      local loopback = table.concat(online.curl_args("GET", "http://localhost:8787/x"), " ")
      assert.is_nil(loopback:find("--proto", 1, true))
    end)

    it("escapes quotes and backslashes for curl's config format", function()
      local config = online.curl_config(nil, { handle = 'a"b\\c' })
      -- The JSON's own escapes survive a round trip through curl's unquoting.
      local quoted = config:match('data%-binary = "(.*)"\n')
      local unquoted = quoted:gsub("\\(.)", "%1")
      assert.are.same({ handle = 'a"b\\c' }, vim.json.decode(unquoted))
    end)

    it("reads the status from the last line", function()
      assert.are.same(
        { status = 200, body = { handle = "ana" } },
        online.parse_response('{"handle":"ana"}\n200')
      )
      assert.are.equal(204, online.parse_response("\n204").status)
      assert.are.equal(0, online.parse_response("").status)
      assert.is_nil(online.parse_response("<html>bad gateway</html>\n502").body)
    end)
  end)
end)
