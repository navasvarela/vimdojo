-- Accounts for the leaderboards. Deliberately little: a GitHub numeric id to
-- recognise a returning login, and a public handle. No email, name or avatar.

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  github_id INTEGER NOT NULL UNIQUE,
  -- Null until the player picks one at first login. Lowercase by validation.
  handle TEXT UNIQUE,
  handle_changed_at INTEGER,
  created_at INTEGER NOT NULL
);

-- Only the hash of a token is stored, so a database leak can't log anyone in.
CREATE TABLE tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL CHECK (kind IN ('web', 'plugin')),
  created_at INTEGER NOT NULL,
  last_used_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX tokens_user ON tokens (user_id);
CREATE INDEX tokens_expiry ON tokens (expires_at);

-- A plugin login in progress: GitHub's device code, kept off the player's machine.
CREATE TABLE device_logins (
  id TEXT PRIMARY KEY,
  device_code TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX device_logins_expiry ON device_logins (expires_at);

-- A released handle stays reserved for a while, so nobody can impersonate its
-- previous owner. Unlinked from any account.
CREATE TABLE handle_holds (
  handle TEXT PRIMARY KEY,
  held_until INTEGER NOT NULL
);

-- Fixed-window counters. The subject is a user id, or a salted hash of an IP
-- address whose salt changes daily.
CREATE TABLE rate_limits (
  subject TEXT NOT NULL,
  window_start INTEGER NOT NULL,
  count INTEGER NOT NULL,
  PRIMARY KEY (subject, window_start)
);
CREATE INDEX rate_limits_window ON rate_limits (window_start);
