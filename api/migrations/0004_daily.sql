-- A board for each day's daily challenge. daily_at is when the server entered a
-- run into the daily: it says which day the run counts for, and it breaks ties,
-- so nothing can be backfilled. Usually received_at, but a log seen on an earlier
-- day is entered when it's sent again.
ALTER TABLE runs ADD COLUMN daily_at INTEGER;

-- Counts and handles only, like every board. Kept with the account, and removed
-- with it: holds no keys.
CREATE TABLE daily_entries (
  date TEXT NOT NULL,
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  level_id TEXT NOT NULL,
  keys INTEGER NOT NULL,
  hinted INTEGER NOT NULL,
  first_at INTEGER NOT NULL,
  PRIMARY KEY (date, user_id)
);
CREATE INDEX daily_entries_board ON daily_entries (date, keys, first_at);
