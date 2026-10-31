-- Submitted runs and what the verifier made of them. A key log is a level's
-- solution, so runs are private to their owner; boards only ever show counts.

CREATE TABLE runs (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  level_id TEXT NOT NULL,
  level_hash TEXT NOT NULL,
  -- The same keys on the same level are one run, however often they're submitted.
  log_hash TEXT NOT NULL,
  keys TEXT NOT NULL,
  deltas_ms TEXT NOT NULL,
  nvim TEXT NOT NULL,
  claimed_keys INTEGER NOT NULL,
  claimed_seconds REAL NOT NULL,
  hinted INTEGER NOT NULL,
  status TEXT NOT NULL CHECK (
    status IN ('pending', 'verified', 'mismatch', 'rejected', 'failed', 'unranked', 'not_best')
  ),
  verified_keys INTEGER,
  -- Failed verification tries, so a log that breaks its batch can't retry forever.
  attempts INTEGER NOT NULL DEFAULT 0,
  received_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  UNIQUE (user_id, level_hash, log_hash)
);
CREATE INDEX runs_pending ON runs (received_at) WHERE status = 'pending';
CREATE INDEX runs_expiry ON runs (expires_at);

-- A player's verified best on each version of a level.
CREATE TABLE bests (
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  level_hash TEXT NOT NULL,
  level_id TEXT NOT NULL,
  run_id TEXT NOT NULL,
  keys INTEGER NOT NULL,
  seconds REAL NOT NULL,
  hinted INTEGER NOT NULL,
  -- The server's own time, the only tie-break it can vouch for.
  first_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, level_hash)
);
CREATE INDEX bests_board ON bests (level_hash, keys, first_at);

-- What a replay concluded. Identical logs are common at par, and verify once.
-- Holds no user id, so it says nothing about who played.
CREATE TABLE verdicts (
  level_hash TEXT NOT NULL,
  log_hash TEXT NOT NULL,
  solved_keys INTEGER,
  checked_at INTEGER NOT NULL,
  PRIMARY KEY (level_hash, log_hash)
);

-- Sandbox batches per month, to stop short of the free allowance.
CREATE TABLE verifier_usage (
  month TEXT PRIMARY KEY,
  batches INTEGER NOT NULL
);
