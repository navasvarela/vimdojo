local helpers = require("helpers")
local online = require("vimdojo.online")
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
      online = { enabled = true, auth_path = helpers.temp_dir() .. "/auth.json" },
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
        assert.are.equal(tonumber("600", 8), bit.band(mode, tonumber("777", 8)))
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
