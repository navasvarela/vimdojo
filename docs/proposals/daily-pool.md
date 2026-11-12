# Proposal: a daily pool of its own

## Why

The daily draws from the levels the site can play, so anyone who has finished those
has already solved every daily. A pool of levels that exist only as dailies makes each
day a puzzle nobody has seen, and gives the tricky edge cases a home: they belong in a
daily rather than in a lesson.

## Decisions (2026-11-12)

- **Its own pack,** `challenges/90-daily.json`, on a new `daily` track. It has no lesson
  and no menu entry: a level is reached as the daily on its day, and from the archive
  after that.
- **A weekly ramp.** Each level has a `difficulty` from 1 to 5, and the weekday picks the
  tier: Monday 1, Tuesday 2, Wednesday and Thursday 3, Friday 4, Saturday and Sunday 5.
  Within a tier the levels are shuffled and none comes back until the tier has been
  played through.
- **21 levels to start:** 3 at each one-day tier and 6 at each two-day tier, so every
  tier lasts three weeks.
- **An archive.** Every daily since the pool started stays playable, on the site and in
  the plugin, but only after its day. Playing it there doesn't count for that day's board
  or the streak; it has its own level board like any level.
- **Every daily plays in the browser,** so each one must pass the emulation gate and is
  flagged `web_demo`. The site keeps the daily pack out of its level list.
- **Par is the best known route with any keys,** as for Setup levels: a daily doesn't sit
  in the curriculum, so "taught so far" means nothing.
- **A start date in the pack** (`daily_start`). Before it, the old picker (every
  `web_demo` level outside the daily pack) still decides, so the merge, the API deploy and
  the plugin release don't have to land on the same day. The first day is a Monday, so
  the ramp starts easy.

## What else changes

- **Past daily boards name the level that was played.** The API worked out a past day's
  level from the current pool, which has changed under it twice. Entries keep their
  `level_id`, so a past board with entries reads it from them.
- **Next level never leads into the daily pack,** in either client, and the plugin's
  unlock rules skip it, so a future daily can't be reached from the menu.
- **The verifier snapshot is rebuilt,** because the new levels are ranked.
