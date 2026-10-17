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

## Curriculum and par (M3)

- **Par rule:** `par_keys` is the shortest solution that uses only motions
  taught so far in the curriculum (the cumulative `teaches` of every earlier
  level, plus `h j k l`). Beginners can always reach 3 stars with what the game
  has shown them. Players who know more motions (`Gw`, `5w`) can beat par.
  Points are capped at 1000, so beating par only matters for bragging.
- `make par` runs `scripts/par.lua`, a Dijkstra search over cursor positions
  in headless Neovim. For every `cursor_at` level it prints the taught-motions
  optimum (which must equal `par_keys`) and the any-motion optimum. It ignores
  `curswant` and `;`/`,` state, so treat it as an authoring aid, not a test.
  `buffer_equals` pars are reasoned by hand. The solution tests still check
  that each reference solution fits within par.
- The curriculum is 20 levels (6 + 6 + 8) rather than the plan's ~15. Pack 3
  needed one level per operator idea the plan lists (`dw dd cw di" ciw . dap
  yy/p`).
- Levels rely on Neovim's default `nostartofline`, so `gg`/`G` keep the
  column. `basic-motions-06` uses `gg^` so it also works where `gg` jumps to
  the first non-blank.
- `web_demo` flags were removed from the sample levels. M4 sets them only
  after each level is checked in the CodeMirror emulation.

## Web demo (M4)

- **Stack:** Vite + TypeScript, plain DOM (no framework), CodeMirror 6 with
  `@replit/codemirror-vim`. Pack JSON is imported straight from
  `../challenges` with `import.meta.glob`, so the data is never copied. zod
  parses it at the boundary (the JSON Schema stays the contract).
- **Ports:** `goals.ts`, `scoring.ts`, `progress.ts` and `game/session.ts`
  mirror the Lua modules. `tests/fixtures/*.json` drive both test suites.
- **Coordinates:** level data uses Neovim byte columns. `text.ts` converts to
  and from CodeMirror's UTF-16 offsets at the editor boundary.
- **Emulation gate:** `src/emulation.browser.test.ts` runs every level's
  reference solution through the emulation in real Chromium (Vitest browser
  mode + Playwright). Every `web_demo` level must pass. jsdom can't do this:
  the emulation moves vertically by measuring layout, which jsdom doesn't
  implement, so `j`/`k` broke there. All 20 levels pass in Chromium. Nine
  (three per pack) are flagged `web_demo`, so the demo stays a taste rather
  than the whole game.
- **Insert mode in tests:** in a browser, typed characters reach Insert mode
  through DOM input, not the Vim key handler. `typeKeys()` inserts them
  directly to match.
- **Key counting:** a capture-phase `keydown` listener on the editor counts
  every key except modifier-only, empty and Cmd/Meta events. Counts can
  differ from Neovim in edge cases (IME composition, OS key repeat rates), so
  web scores are indicative.
- **Controls:** `Alt+H` hint, `Alt+R` reset, `Alt+N` next. Alt combos never
  reach Vim and are not counted. `KeyboardEvent.code` is used because
  Alt+letter types a different character on macOS. The results card takes
  focus, with `N`/Enter for next and `R` to retry.
- **Unlocking:** every demo level is unlocked. The demo is a sampler, so
  progression gating would only hide content. Stars and bests are still kept.
- **Progress:** `localStorage` key `vimdojo.progress`, in the same shape as
  the plugin's `progress.json`. Export/Import use that file. Every storage
  access is guarded, and a disabled or full storage only shows a notice.
- **Bundle:** the demo chunk (CodeMirror + Vim, ~134 kB gzip) loads lazily
  when its section nears the viewport. The landing page's initial JS is
  ~1.5 kB gzip.
