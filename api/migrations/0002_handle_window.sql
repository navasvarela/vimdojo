-- When the player first picked a handle. A new handle can be changed freely for a
-- day, so a typo at sign-up doesn't last a month.
ALTER TABLE users ADD COLUMN handle_first_set_at INTEGER;
UPDATE users SET handle_first_set_at = handle_changed_at WHERE handle IS NOT NULL;
