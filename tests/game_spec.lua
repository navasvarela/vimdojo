local game = require("vimdojo.game")

local LEVEL = { id = "x", par_keys = 5, par_seconds = 8 }

---@return vimdojo.Session session
---@return fun(seconds: number) advance Moves the fake clock forward.
local function new_session()
  local now = 100
  local session = game.new(LEVEL, function()
    return now
  end)
  return session, function(seconds)
    now = now + seconds
  end
end

describe("game session", function()
  it("does not start the timer until the first key", function()
    local session, advance = new_session()
    advance(30)
    assert.are.equal(game.State.Ready, session.state)
    assert.are.equal(0, session:elapsed())

    session:count_keys(1)
    advance(2.5)
    assert.are.equal(game.State.Playing, session.state)
    assert.are.equal(2.5, session:elapsed())
  end)

  it("takes back control keys and restarts the timer when none remain", function()
    local session, advance = new_session()
    session:count_keys(2)
    advance(3)
    session:uncount_keys(2)
    assert.are.equal(0, session.keys)
    assert.are.equal(game.State.Ready, session.state)

    session:count_keys(1)
    advance(1)
    assert.are.equal(1, session:elapsed())
  end)

  it("keeps counting when only part of the keys are taken back", function()
    local session = new_session()
    session:count_keys(5)
    session:uncount_keys(2)
    assert.are.equal(3, session.keys)
    assert.is_true(session:is_playing())
  end)

  it("scores the attempt on finish and rounds seconds to centiseconds", function()
    local session, advance = new_session()
    session:count_keys(5)
    advance(4.123)
    local outcome = session:finish()
    assert.are.same({ keys = 5, seconds = 4.12, hinted = false, stars = 3, points = 1000 }, outcome)
  end)

  it("ignores keys after finishing and freezes the time", function()
    local session, advance = new_session()
    session:count_keys(5)
    advance(4)
    session:finish()
    session:count_keys(3)
    advance(10)
    assert.are.equal(5, session.keys)
    assert.are.equal(4, session:elapsed())
  end)

  it("carries the hint into the score", function()
    local session, advance = new_session()
    session:use_hint()
    session:count_keys(5)
    advance(1)
    assert.are.equal(2, session:finish().stars)
  end)
end)
