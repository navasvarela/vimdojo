# Decisions

Short notes on choices made while building vimdojo. Newest at the bottom.

## Coordinates

`cursor_start` and the `cursor_at` goal use `[line, col]` with a **1-based
line and 0-based byte column**, matching `nvim_win_get_cursor()`. The web port
converts at its boundary.

## Tooling

- Tests use plenary.nvim's busted runner, cloned into `.deps/` by `make deps`.
  It is a dev-only dependency; the plugin has none at runtime.
- Lint is `stylua` (format) and `selene` (static analysis). Selene's `vim`
  standard library is declared in `vim.yml`, which also allows the busted test
  globals.
- Pack files are validated against `challenges/schema.json` (JSON Schema
  2020-12) with `ajv-cli` in CI.

## Plan corrections

- The plan's example level ("Kill the typo") used the solution `fxdw`, which
  leaves `fjumps` behind because `dw` starts on the `x`. The correct reference
  solution is `ffdw`. This is exactly what the solution tests exist to catch.

## Key counting

One physical key is one keystroke: `d2w` is 3, `<Esc>` is 1, `<C-r>` is 1.
`keys.split()` applies the same rule to a key-notation string, which is how
the solution tests compare a reference solution against `par_keys`.

## Scoring (`lua/vimdojo/scoring.lua`)

- Stars: 3 when keys <= par_keys **and** seconds <= par_seconds; 2 when
  keys <= 1.5 x par_keys; otherwise 1 (completion).
- Points (0-1000): `1000 * (0.7 * key_ratio + 0.3 * time_ratio)`, where a
  ratio is 1 at or under par and `par / actual` above it. Rounded half up.
- Using the hint caps the attempt at 2 stars and multiplies points by 0.8.
- `tests/fixtures/scoring.json` pins the behavior for both the Lua and TS ports.

## Progress

- Unlock rules and record merging live in a pure `progress.lua`, separate from
  file I/O in `storage.lua`. (The plan lists only `storage.lua`; this split keeps
  the logic testable without the filesystem.)
- `best_keys` and `best_seconds` are tracked independently, so they may come
  from different attempts. `stars` is the best ever earned.
- `unlock_all` is a choice of unlock strategy (`unlocked_all` vs
  `unlocked_by_progress`) rather than a flag threaded through the rules.
- A progress file that fails to parse, has an unknown `version`, or contains a
  malformed record is renamed to `progress.json.corrupt-<unix time>` and play
  starts fresh. Nothing is ever deleted.

## Mappings

Reference solutions are fed with `noremap`, so levels are judged against stock
Vim behavior. Players keep their own mappings in the game buffer; a level that
a custom mapping changes is the player's config, not a bug in the level.

## Game loop (M2)

- **Control keys** are buffer-local Normal-mode mappings in the level buffer,
  configurable via `setup({ keymaps = { hint, reset, quit } })`. Defaults:
  `<leader>h`, `<leader>r`, `<Esc><Esc>`. `vim.on_key` sees them before the
  mapping runs, so each control subtracts its own key count (`<leader>` counts
  as one key). If that leaves zero keys, the timer resets as if the attempt
  had not started, so reading the hint first costs no time.
- **Attempts finish in Normal mode.** The goal is checked on `TextChanged`,
  `CursorMoved` and `ModeChanged` into Normal mode, not in Insert mode. A
  change is done once the player presses `<Esc>`, which matches how the
  reference solutions run (`feedkeys` with `x` leaves Insert mode). The plan
  suggested also checking `TextChangedI`/`CursorMovedI`. That would end
  `ciwfoo<Esc>` before the `<Esc>` and make par off by one.
- **Mouse:** `'mouse'` is a global option, so it is saved, cleared for the
  whole session and restored on every exit path. Without this, a click could
  solve a `cursor_at` level with zero keys.
- **Goal visibility:** `cursor_at` targets are highlighted in the buffer
  (`VimDojoTarget`). `buffer_equals` targets are printed in the header.
- **Hints:** the header reserves a hint line sized for the real hint, so
  showing it never resizes or moves windows. A hint survives a reset within
  the same level visit.
- **Reset** restores the text in place with `undolevels=-1`, so `u` cannot
  undo the level back to an empty buffer.
- **End-to-end tests** (`tests/app_spec.lua`) run a child `nvim --embed` and
  drive it with `nvim_input`, so key capture, mappings and autocmds run exactly
  as they do for a real player.
