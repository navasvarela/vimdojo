-- The online flow with nothing replaced: a real Neovim with the plugin's default
-- dependencies, real curl, and an HTTP server on loopback. online_spec.lua covers the
-- branches, but it supplies its own dependencies, which is how v0.7.0 reached main with a
-- verified run crashing on a default that didn't exist.
local helpers = require("helpers")
local player_mod = require("player")

local uv = vim.uv or vim.loop

local LEVEL = "basic-motions-01"
local SOLUTION = "jjjll"
local TOKEN = "vdj_test-token"
local HTTP_REASON = { [200] = "OK", [202] = "Accepted" }

---@alias ServerRequest { method: string, path: string, authorization: string|nil, body: string }

--- Answers one request per connection, once its headers and body have arrived.
---@param respond fun(request: ServerRequest): integer, table
---@return integer port
---@return ServerRequest[] requests
---@return fun() stop
local function start_server(respond)
  local requests = {}
  local server = assert(uv.new_tcp())
  assert(server:bind("127.0.0.1", 0))
  assert(server:listen(16, function()
    local client = assert(uv.new_tcp())
    server:accept(client)
    local received = ""
    client:read_start(function(_, chunk)
      if not chunk then
        client:close()
        return
      end
      received = received .. chunk
      local headers, body = received:match("^(.-)\r\n\r\n(.*)$")
      local length = headers and tonumber(headers:lower():match("content%-length: (%d+)")) or 0
      if not headers or #body < length then
        return
      end
      local method, path = headers:match("^(%u+) (%S+)")
      local request = {
        method = method,
        path = path,
        authorization = headers:match("[Aa]uthorization: ([^\r\n]+)"),
        body = body,
      }
      table.insert(requests, request)
      local status, answer = respond(request)
      local text = vim.json.encode(answer)
      client:write(
        ("HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\n"):format(
          status,
          HTTP_REASON[status],
          #text
        )
          .. "Connection: close\r\n\r\n"
          .. text
      )
    end)
  end))
  return server:getsockname().port, requests, function()
    server:close()
  end
end

describe("the online flow over real HTTP", function()
  local player, stop_server

  after_each(function()
    player:stop()
    stop_server()
  end)

  it("submits a run with the default dependencies and shows the verdict", function()
    local port, requests, stop = start_server(function(request)
      if request.method == "POST" then
        return 202, { id = "r1", status = "pending" }
      elseif request.path:match("/runs/r1$") then
        return 200, { status = "verified", verified_keys = 5, claimed_keys = 5, level_id = LEVEL }
      elseif request.path:match("/me$") then
        return 200, { rank = 4 }
      end
      return 200, { entries = {} }
    end)
    stop_server = stop
    player = player_mod.spawn({
      online = {
        enabled = true,
        url = ("http://127.0.0.1:%d"):format(port),
        auth_path = helpers.temp_dir() .. "/auth.json",
        outbox_path = helpers.temp_dir() .. "/outbox.json",
      },
    })
    player:lua(
      [[
        require("vimdojo.online").save_token(...)
        _G.notified = {}
        vim.notify = function(message)
          table.insert(_G.notified, message)
        end
      ]],
      TOKEN
    )
    assert.is_true(player:start(LEVEL))
    player:type(SOLUTION)
    assert.is_truthy(player:wait_for_record(LEVEL))
    assert.is_true(
      player:wait_for("require('vimdojo.app').current().session:is_finished()"),
      "the level never finished"
    )

    player:lua("vim.v.errmsg = ''")
    player:input("s")

    local verdict = player:poll(function()
      local notified = player:lua("return _G.notified")
      for _, message in ipairs(notified) do
        if message:find("You're #4", 1, true) then
          return message
        end
      end
    end)
    assert.is_truthy(verdict, vim.inspect(player:lua("return _G.notified")))
    assert.are.equal("", player:lua("return vim.v.errmsg"))
    assert.are.equal("POST", requests[1].method)
    assert.are.equal("Bearer " .. TOKEN, requests[1].authorization)
    assert.are.same(
      LEVEL,
      vim.json.decode(requests[1].body).level_id,
      "the run names the level it's for"
    )
  end)
end)
