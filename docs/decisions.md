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

Superseded by the clean room (M7): levels run in a stock Neovim, so neither
the player's mappings nor their plugins apply, unless they choose
`config = "mine"`. Reference solutions are still typed with stock behavior.

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

## Landing page and deploy (M5)

- **Curriculum is rendered at build time.** A small Vite plugin
  (`web/build/curriculum.ts`) reads `challenges/*.json` and writes the pack
  list into `index.html`. The page stays in sync with the data without
  shipping the packs or zod in the initial load. It only transforms the site's
  own `index.html`. An earlier version also hit Vitest's browser-runner page,
  which silently stopped the emulation tests from running.
- **Hero animation** is a scripted replay in plain DOM (`landing/hero-demo.ts`)
  rather than a GIF or the real editor. It is crisp at any size, tiny, and
  respects `prefers-reduced-motion` with a static solved frame. It is
  `aria-hidden` with a text description.
- **Repo links** come from `VITE_REPO` (`web/.env`; CI sets it from
  `github.repository`). `index.html` uses Vite's `%VITE_REPO%` replacement,
  and the Pages build sets `VITE_BASE=/<repo-name>/`.
- The **install snippets** omit `setup()`: the plugin works with defaults, and
  every `:VimDojo` entry point lazy-loads it. Copy buttons fall back to
  selecting the text when the Clipboard API is unavailable.
- Grid tracks use `minmax(0, 1fr)` so long `<pre>` snippets scroll inside
  their box instead of widening the page on phones.

## Release and packaging (M6)

- **rocks.nvim / LuaRocks:** `release.yml` (nvim-neorocks/luarocks-tag-release)
  publishes on `v*` tags. A rock installs `lua/` into the Lua tree but copies
  `plugin/`, `doc/` and `challenges/` into the rock directory on
  'runtimepath', so `challenges.default_dir()` falls back to the runtimepath
  entry that provides `plugin/vimdojo.lua`. Verified with a local
  `luarocks make` into a temporary tree.
- **Help:** `doc/vimdojo.txt`. `make doc` (run in CI) fails on malformed or
  duplicate tags. `doc/tags` is generated by plugin managers and gitignored.
- **README GIF:** recorded with VHS from `docs/demo.tape` (`make gif`), so it
  can be regenerated whenever the UI changes.

## Clean-room engine (M7)

- **Every level runs in a child Neovim** (`nvim --clean -n -i NONE`) inside
  a terminal window owned by the game (`room.lua`, `room/child.lua`). The
  player's registers, options, mappings, plugins, history and windows are
  never touched. Every level runs against the same stock defaults its
  reference solution is tested with. This was decision D1 in PLAN-v2.
- **Wiring:** the child gets the parent's `v:servername` and a room id
  through the environment. It connects back, names its channel with
  `nvim_set_client_info`, and notifies the parent with `nvim_exec_lua`
  notifications. Lua can't ask which channel a call arrived on
  (`nvim_get_api_info` is RPC-only), so the parent finds the child's channel
  by that client name in `nvim_list_chans()`. A single socket carries both
  directions.
- **The child loads its modules from the parent's install.** It runs with
  `--clean`, so `VIMDOJO_LUA_DIR` (the directory that holds `vimdojo/`) is
  prepended to its `package.path`. This works for git checkouts and LuaRocks
  trees alike.
- **The child owns the goal checks.** It evaluates the goal on
  `TextChanged`, `CursorMoved` and `ModeChanged` into Normal mode, freezes
  the buffer, and notifies "solved". No snapshot polling is needed, and the
  check sees exactly what the player sees.
- **Key counting stays in the parent**, through `vim.on_key` while the room
  window is focused and in Terminal mode. Keys replayed by macros aren't
  counted (measured: `3@a` counts 3). Command-line keys are.
- **Control keys** (hint, reset, quit) are buffer-local mappings in the
  child that notify the parent. The parent subtracts their keys, as before.
  The child's `mapleader` is set to the parent's, so `<leader>` means the
  same thing to the player. A fast `<Esc><Esc>` arrives as two Escapes, not
  `<M-Esc>` (measured).
- **Terminal-mode mappings are suspended** while a level is played and
  restored with `mapset()` afterwards (`tmaps.lua`). Otherwise a common user
  mapping like `tnoremap <Esc> <C-\><C-n>` would make `<Esc>` unusable
  inside levels. There's an end-to-end test with exactly that mapping.
- **`config = "mine"`** starts the child without `--clean`, so players can
  practice with their own setup. Shada and swap stay off either way.
- If the room's Neovim exits (`:q` inside the level), the level closes
  cleanly.
- **Tests:** `tests/player.lua` drives an embedded parent with
  `nvim_input()`, so the end-to-end and solution specs exercise the full
  path: terminal, child mappings, goal checks and RPC. Typing pauses 120 ms
  after `<Esc>`, because the child's TUI waits `ttimeoutlen` to tell Escape
  from an Alt sequence. Solution specs also assert the recorded key count
  equals the solution's length, which checks counting through the terminal.

## Schema v2 (M8)

- **Tracks:** packs declare `track` (`motions`, `usage` or `setup`; default
  `motions`). Each track's first pack is open from the start, and packs
  unlock in `order` within their own track (D3 in PLAN-v2). Pack `order`
  stays globally unique, so packs keep one numbering across tracks.
- **Version gates:** `requires = { nvim = "0.11" }`. Levels this Neovim
  can't run show "needs Neovim X" in the menu, can't be started, are skipped
  by "next level", and **don't block unlocking** (otherwise a 0.10 user would
  be stuck behind one 0.11 level). Solution tests mark them pending (D4).
- **Options** are applied like `:set` in the level's clean room. Validation
  rejects unknown option names via `nvim_get_option_info2`, so a typo fails
  CI instead of silently not applying.
- **Presets:** `registers` (a string is charwise, a list is linewise) and
  buffer `marks` a-z. Quickfix and diagnostics presets arrive with the Usage
  track (M11), which needs them.
- **Goals:** `register_contains` (lines, plus an optional `linewise`) and
  `all_of` (composite, recursive). Snapshots carry only the registers the
  goal reads (`goals.registers()`). Registers a goal reads are cleared on
  every load and reset, so a reset can't inherit a register from the previous
  attempt.
- **Deviation from PLAN-v2:** the multi-file `files` field moves to M11,
  where the workspace engine that uses it lands. Adding it now would be
  schema without behavior.
- **`challenges_dir` setup option:** load packs from another directory.
  Authors can play-test a pack before contributing it, and the test suite
  uses it for `tests/fixtures/packs/`, which exercises every v2 feature end
  to end in real clean rooms.
- **Web:** zod mirrors the recursive goal union (`all_of` uses a getter for
  recursion). The emulation snapshots and presets registers through
  codemirror-vim's register controller, verified in Chromium against the
  fixture levels. Mark presets and options aren't emulated; such levels
  can't pass the emulation gate, so they never get flagged `web_demo`.

## Motions wave 1 (M9)

- **Four packs, 22 levels:** Visual Mode (5), Search (5), Text Objects (6),
  Transform (6). PLAN-v2 sketched 24 levels.
- **Levels were dropped or changed to keep the par rule honest.** A level only
  teaches well if its new key is the shortest route among the taught keys.
  - Plain `v` + operator, `V` + `>`, and `o` lose to an operator + motion or a
    count (`df)`, `>2j`), so Visual teaches block mode (`<C-v>` with `I`, `$A`,
    `d`, `c`) and pasting over a selection (`viwp`).
  - Search targets sit mid-line on far lines, because counts are cheap (`16j`
    is 3 keys).
  - "Whole words" (`\<\>`) and the search-offset level were dropped: every
    variant had a shorter trick with what's already taught.
- **The par finder searches too:** `/xx<CR>` and `?xx<CR>` for buffer
  substrings up to 4 characters, plus `*`, `#`, and `j`/`k` counts up to the
  level's length. `n` isn't modeled (it depends on the last search), so the
  `n` level's par is worked out by hand.
- **Clever pars are fine.** "Change gang" has par 13 via
  `w#cgnuser<Esc>...`: `#` wraps to the last match, so `.` skips the line to
  leave alone without needing `n`. A straightforward `/tmp<CR>cgn...nn.` (18)
  still earns 2 stars.
- **The emulation gate now presses real keys** (`userEvent.keyboard` through
  Playwright) instead of calling `Vim.handleKey`. Typing into the search
  prompt, Insert mode and Replace mode now go through the browser exactly as
  they would for a player. That turned the search levels and `R` from "fail"
  into "ok".
- **Real emulation gaps found** (these levels stay Neovim-only): `<C-v>`
  block mode doesn't engage, `p` over a visual selection pastes after it,
  `cit`, `g<C-a>`, linewise `yi{`, and `#` + `cgn` match selection. Of the 13
  new levels that pass, six are flagged `web_demo`: `/`, `*`, `ci(`, `daw`,
  `<C-a>` and `R`.

## Motions wave 2 (M10)

- **Packs reshaped for honest pars.** PLAN-v2 sketched separate Registers (6),
  Macros (6) and Ex (7) packs. Many register ideas have a shorter route with
  keys already taught: `yy9jp` + `kdd` beats `"0p`, typing `444` beats
  `<C-r>=12*37`, and `40i-` beats an expression for repeated text. And
  `yy9p` + `g<C-a>` beats a numbering macro. Those were dropped. The result
  is **08 Registers and Macros** (5 levels; macros live in registers anyway)
  and **09 Ex Power** (6). The Usage and Setup packs therefore start at
  order 10.
- Every Ex level was checked against the macro and `cgn` alternatives that
  are taught by then. `:%norm wdw` ties a `wdwj^` macro at 11, which is
  accepted.
- "Until it stops" uses `k` after `dd` inside the macro, so the next search
  starts above the cursor and back-to-back DEBUG lines aren't skipped.
- The emulation handles macros, `"A` appends, `<C-r>` and most Ex commands.
  Four levels joined the demo (19 in total). `:m` and the
  stop-on-failure macro don't match Neovim there.

## Setup-track engine (M12)

- **The room child runs the checks**, the same way it owns every other goal
  check (M7). On `TextChanged` and on entering Normal mode it restarts a
  400 ms debounce, then hands the buffer to `sandbox.lua`. The verdict is
  stored with the buffer's `changedtick`, and snapshots carry it as
  `config_passed` only while the text is unchanged. So `config_probes` stays
  a pure lookup in `goals.lua`, works inside `all_of`, and a stale verdict
  can never solve a level. A newer check kills the one in flight.
- **Sandbox:** `nvim --headless --clean -n -i NONE -u shim.lua -l
  probes/run.lua job.json`, with every `XDG_*` variable (including
  `XDG_CONFIG_DIRS` and `XDG_DATA_DIRS`, so system-wide site directories
  stay out) and `NVIM_APPNAME` pointing into a temporary directory that is
  deleted afterwards. The shim loads the player's config at the point of
  startup where a real `init.lua` loads, before filetype detection and
  plugins, and sets `$MYVIMRC`. The report comes back as a JSON file, not
  stdout, so whatever the config prints can't corrupt it. About 50 ms per
  run on a laptop.
- **This is isolation, not a security sandbox.** The code is the player's
  own (or a pack author's, for starters), running with their permissions.
  The point is that it never touches their real config, data or session.
- **The 3 s timeout uses SIGKILL.** `vim.system`'s own timeout sends
  SIGTERM, which Neovim handles on its event loop; a config stuck in
  `while true do end` never returns to the loop and was never killed
  (measured).
- **Load errors point at a line.** The config is compiled with chunk name
  `init.lua` (Lua truncates long temp paths in messages), run under
  `xpcall(debug.traceback)`, and the innermost `init.lua:N:` frame wins, so
  an error raised inside the runtime (`vim.keymap.set` with a `nil` rhs)
  still points at the player's line. Probes still run after a load error,
  so the player sees everything that's wrong at once.
- **Feedback is diagnostics in the room's buffer**: the load error on its
  line, the first failed probe (plus a count) on the last line, as virtual
  text. They're drawn by the child, so they cost no keys and can't move
  the header. The header lists every probe's description.
- **Probes** are declarative data in `lua/vimdojo/probes/`, one module per
  kind: `option`, `keys`, `filetype`, `command`, `source_twice`,
  `extmarks_after` and the `lua` escape hatch. They're validated when packs
  load (unknown options and events are errors) and in `schema.json`. Each
  runs from one window on an empty buffer. `keys` and `extmarks_after` edit
  a real fixture file so `:w` and `BufWritePre` work, and expand `<leader>`
  to the leader the config set. `extmarks_after` counts every namespace by
  default because the yank highlight's namespace was renamed between
  versions.
- **`option` reads from a new buffer**, so a buffer-local value set only on
  the startup buffer (`vim.bo.shiftwidth = 2`) doesn't pass: new files
  wouldn't get it.
- **The web parses `config_probes` loosely**: only `kind` (as an enum) and
  `description`. The browser never runs probes; the schema and the Lua
  validator are the contract. `isMet` is always false there, the emulation
  gate skips such levels, and loading a pack rejects `web_demo` on them.
- **Fixture levels** in `tests/fixtures/packs/02-v2-setup.json` (an option,
  a `<leader>w` mapping, a `:Trim` command) are solved end to end through
  real rooms by `solutions_spec.lua`. `probes_spec.lua` runs every kind in
  a real sandbox against a passing and a failing config.
- **Plenary's per-file timeout is raised to 10 minutes.** Its 50 s default
  killed `solutions_spec.lua` partway through on a busy laptop once M9 and
  M10 added levels, before it reached the fixture packs. CI finishes it in
  seconds.

## Usage track (M11)

- **Workspaces:** a level can ship `files` (path -> lines) plus `open`
  instead of `start_text`. The room writes them into a fresh temp directory,
  `:cd`s there, and edits `open`. `start_text` is derived from the open file
  when packs load (Lua `challenges.level_text`, and a zod transform in TS),
  so the rest of the engine is unchanged and nothing is duplicated. Paths
  must stay inside the workspace (no absolute paths, no `..`).
- The workspace path is taken from `getcwd()` after the `:cd`, not from
  `tempname()`. On macOS the temp dir sits under the `/var` ->
  `/private/var` symlink, and buffer names use the resolved form.
- **`preset.commands`** (Ex commands run after the level is built) set up
  splits, quickfix lists (`vimgrep /x/j **` + `cfirst`), a previous `:s`,
  and diagnostics (`lua vim.diagnostic.set(...)`). This is trusted data from
  the repo, and it only runs in the clean room.
- **Goals:** `files_equal` compares each file's buffer if it's loaded
  (unsaved edits count), and its disk contents otherwise. `layout` compares
  the current tab's `winlayout()` with workspace file names in the leaves.
  Both are Neovim-only. `challenges.needs_neovim()` rejects `web_demo` on
  them, on Setup levels, and on levels with preset commands.
- **The room now behaves like an editor, not a single buffer.** Controls are
  global mappings and goal checks are global autocmds, because players move
  between windows and files. Checks are coalesced with `vim.schedule`,
  since a split fires several events. `WinResized` is watched because moving
  a window (`<C-w>L`) enters, creates and closes none. A load/reset tears
  everything down first: one tab, one window, no other buffers, an empty
  quickfix list, no arguments and no jumps.
- **Key notation:** `<C-^>`, `<C-]>` and other modifier + punctuation keys
  count as one key (Lua and TS). Before, they were split into characters,
  which broke both par checks and typing in tests.
- **Packs:** 10 Windows and Buffers (6), 11 Project-Wide Edits (3), 12
  Neovim Built-ins (4; the quickfix level `requires` 0.11). Most window
  levels are 1-2 keys by nature: the lesson is the command, and par is
  trivially honest. PLAN-v2's "global marks" and "Breathing room"
  (`]<Space>`) levels were dropped: the first needs uppercase-mark presets
  across files, and the second ties `o<Esc>`.
- **Windows `:find` quirk:** on Windows, file-in-path completion returns
  nothing when `path` is exactly `.,**` and the current file sits in the
  working directory (measured in CI; `**`, `./**` and `.,,,**` all work).
  `project-03` uses `.,,,**`, which is what Neovim's default `.,,` becomes
  after the common `set path+=**`. Diagnosed by probing a real room on a
  Windows runner. Failing solution tests now print the room's `:messages`.

## Setup curriculum (M13)

- **Four packs, 18 levels:** Options and Keymaps (6), Autocommands and
  Commands (4), Fix the Broken Config (5), Modern Neovim (3, `requires`
  0.11). Each starter config fails its probes (the solution tests now prove
  it), and each reference edit passes them in a real room.
- **Par rule for Setup:** the track is independent (D3), so "motions taught
  so far" doesn't apply. Par is the best known keystroke edit of the
  starter config, with any keys.
- **Probes must test the real outcome.** The first "Trim on save" probe
  checked the buffer after `:w`. With `BufWritePost`, Neovim clears
  `modified` after the autocommand, so the buffer looked clean although the
  file on disk was untrimmed, and the wrong config passed. The probe now
  runs `:w<CR>:e!<CR>` and compares what was actually saved.
- **Comment continuation:** `o` on a Lua comment line continues the comment,
  so levels that add a line start the cursor on code, not on a comment.
- **Levels this Neovim can't run** (`requires` newer) only get their goal's
  shape checked when packs load. Otherwise a 0.11 option name in a probe
  (`winborder`) would make every pack fail to load on 0.10. CI now also runs
  the plugin tests on **Neovim 0.10.4**, the oldest supported release.
- When a starter config already passes, the level solves itself and the
  checks stop. The solution test now reports exactly that, instead of "never
  checked".
- **Version drift caught by CI:** Neovim nightly accepts Lua tables for
  `vim.o` list options, so a "vim.o is not vim.opt" level stopped being a
  bug there. It was replaced by `vim.g.number = true`, which is wrong on
  every version. On 0.10 the `extmarks_after` probe skips namespaces that
  `nvim_buf_get_extmarks` rejects.

## Web refresh (M14)

- The landing page's curriculum is grouped by track (Motions, Usage, Setup),
  each with a one-line explanation and its level count, still rendered at
  build time from `challenges/*.json`. Usage and Setup carry a "Neovim only"
  badge: they need real files, windows or a config, which the browser demo
  can't provide.
- Pack cards lay out in a responsive grid (two columns where they fit), so
  16 packs don't make the page endless.
- Copy now covers all three tracks and invites level contributions. The
  stale "coming next" note is gone.

## Custom domain

The site moved to https://vimdojo.org (GitHub Pages custom domain, deployed
by Actions; the domain is set in the repository's Pages settings, so no CNAME
file is needed). It is served from the domain root, so Vite's `base` is now
`/` by default. With the old `/vimdojo/` base, every script, stylesheet and
image 404'd on the custom domain, and the page rendered unstyled with no demo.

## Visit analytics

To see where launch visitors come from, the site counts visits with
**Cloudflare Web Analytics**. This supersedes PLAN.md's "No analytics or
third-party trackers in the MVP".

- **Why Cloudflare:** the domains are already registered there, it's free,
  and it's cookieless and doesn't fingerprint visitors, so no consent banner
  is needed. It reports visits, pages, referrers and countries, which is
  what a launch needs.
- **Why not Google Analytics:** it sets cookies, so EU visitors would need a
  consent banner, and the page used to promise "no tracking". The footer
  now says what's counted instead.
- **Beacon, not automatic setup:** Cloudflare only injects the script itself
  when it proxies the site. vimdojo.org's DNS records point straight at
  GitHub Pages (not proxied), because GitHub Pages issues and renews the
  certificate and that's fragile behind a proxy. So `web/build/analytics.ts`
  adds the beacon to index.html at build time.
- **Only on the deployed site:** the beacon is added only when
  `VITE_CF_BEACON_TOKEN` is set. The Pages workflow sets it from the
  `CF_WEB_ANALYTICS_TOKEN` repository variable, so dev servers, tests and
  forks never report. The token is public by design (it ends up in the page).
- The plugin itself still makes no network calls.

## Community, phase 0 (no backend)

The first step of `docs/proposals/leaderboard-and-community.md` (PR #2):
features that need no server, so the game stays offline and free to host.

- **Pasted text costs what typing it would**: one key per character, one
  `<CR>` per line break. In the plugin a paste never reaches `vim.on_key`
  (measured on 0.12: `nvim_paste` into a terminal buffer fired no key
  events), so `keys.capture` wraps `vim.paste` while a level is active and
  restores it afterwards. The web demo counts `paste` and `drop` events on
  the editor. Before this, pasting a solution cost zero keys.
- **Key logs are not recorded yet**, although the proposal lists them in
  phase 0. Nothing reads them until phase 1 submits runs, they would change
  the progress format in both clients, and `progress.json` is exportable,
  so storing them there would hand solutions to anyone a player shares
  progress with. They come with phase 1, in their own file.
- **Daily challenge:** one level per UTC day from the date alone, so it
  works offline and the plugin and the site agree. The pool is the demo
  levels (anyone can play the daily in the browser), sorted by id. Days run
  in cycles as long as the pool: each cycle plays every level once in an
  order shuffled from the cycle number with MINSTD (Park-Miller), whose
  products stay exact in both Lua doubles and JS numbers. A cycle never
  starts with the level the previous one ended on. `tests/fixtures/daily.json`
  pins both ports. The daily ignores pack locks, and solving it is recorded
  as that level's progress.
- Accepted: adding or removing a demo level reshuffles the schedule, so for
  a while an older plugin and the site can show different dailies. A
  hand-written `daily.json` rotation would avoid it, at the cost of someone
  keeping it filled in.
- **Share text** (`y` in the plugin's results card, "Copy result" on the
  site) names the level or the daily's date and the score, never the keys,
  so it can be posted without spoiling the solution. Seconds are rounded
  half up to tenths before formatting: Lua's `%.1f` rounds an exact tie such
  as 4.25 to even and JavaScript's `toFixed` rounds it up, and the shared
  fixture caught the two texts disagreeing.
- **Authors:** packs and levels take an optional `authors` list of GitHub
  handles (a level's replaces its pack's), validated with GitHub's handle
  rule in the schema, Lua and TS. The site renders a "Levels by" line from
  them at build time, like the curriculum. The 16 existing packs credit
  @navasvarela.
- **Untrusted pull requests in CI:** a level PR runs its own content (keys
  typed into Neovim, Lua in Setup levels and probes), so CI treats forks as
  untrusted. Workflows trigger on `pull_request` only, the token is
  read-only, checkouts don't persist it, jobs have timeouts, and
  third-party actions are pinned to commit SHAs (GitHub's own `actions/*`
  stay on tags). The PR template asks authors to flag `preset.commands`,
  `lua` probes and Setup starters, which run on players' machines, and
  CODEOWNERS requests the maintainer's review on every PR. In the repo
  settings, "Require approval for all outside collaborators" should be on
  for fork workflows.

## Lint and format for TypeScript and JSON

- **Biome, not ESLint + Prettier.** The web project is on TypeScript 7, the
  native compiler, which has no JavaScript compiler API
  (`require("typescript").createProgram` is undefined). typescript-eslint's
  type-aware rules need that API and support TypeScript only up to `<6.1`
  (as of 8.72), so `no-floating-promises` and friends can't run.
  Biome 2 infers types itself and works with TS 7 today, and one tool
  covers lint and format for TS, CSS and JSON.
- `biome.json` sits at the repo root so the format check also covers the
  level packs (`challenges/*.json`) and the shared fixtures.
- Beyond the recommended preset, the rules that enforce the house style are
  errors: `noExplicitAny`, `noNonNullAssertion`, `useImportType`,
  `useExportType`, and the type-aware `noFloatingPromises` and
  `noMisusedPromises` (nursery rules in 2.5). `useLiteralKeys` is off: the
  code reads index signatures with brackets (`process.env["VITE_BASE"]`) on
  purpose. Line width 100 matched the existing code with the fewest changes.
- The CodeMirror cursor and selection overrides keep `!important` (its
  runtime theme wins otherwise), inside a `biome-ignore` range.

## Leaderboards: decisions for phase 1 (2026-10-30)

PLAN-v3.md records the full table. The two departures from the proposal:

- **Stack: Cloudflare Workers + D1, with Vercel Sandbox for replays**,
  instead of all-Vercel with DynamoDB. The domain's DNS and the site's
  analytics are already on Cloudflare, D1 needs no card and gives SQL for
  boards, and Vercel Sandbox is still the free way to run Neovim in a
  microVM. The SDK accepts an access token outside Vercel. Accepted: two
  vendors, and the Workers runtime (10 ms CPU on the free plan) for the API.
- **The site stays on GitHub Pages.** `api.vimdojo.org` is same-site with
  vimdojo.org, so a `SameSite=Lax` cookie works without moving the site.
- **EU residency:** D1 is created with `jurisdiction: "eu"`. Vercel Sandbox
  may run elsewhere, so verifier jobs carry only the level and the key log,
  never a user id or handle.
## M15: the replay verifier, local half

- **All 66 Motions and Usage reference solutions verify** in
  `nvim --embed --clean --headless` with exactly their own key count, at a
  median of about 40 ms per replay (Neovim 0.12.6, macOS). The divergences
  the proposal feared (Alt chords from a fast `<Esc>`, `<C-i>` vs `<Tab>`)
  don't show up in the shipped solutions: without a terminal in between,
  no escape-sequence timeout applies, so no pause after `<Esc>` is needed.
- **The level is built by the room's own Lua** (`room/child.lua`'s
  `set_ui_options` and `load`, now exported with `buffer`), before any key
  is replayed, so replays see what the live room shows. The room's goal
  checks are removed straight after: the harness checks the goal itself.
- **State is read through the C API and builtin Vimscript functions only**
  (`nvim_buf_get_lines`, `getreg`, `winlayout`...). A replayed log can
  redefine any Lua function in the child, including the room's snapshot,
  but not those. A test redefines `snapshot` and checks it can't fake a
  solve.
- **The harness is a msgpack-RPC client, not a Neovim**, and answers every
  request from the child with an error. A test makes the replayed Neovim
  call back with `vim.rpcrequest(1, "nvim_exec_lua", ...)` and checks the
  replay carries on.
- **Ordering:** after `nvim_input`, the fast `nvim_get_mode` already sees
  the key (measured over repeated `i`/`<Esc>` rounds), so the loop is: send
  one key, read the mode, and snapshot only in Normal mode when not
  blocking.
- `make verifier-check` and a CI job run the solution replays and the
  adversarial tests (short and long logs, `:lua` routes, a hostile
  callback, an infinite loop, `:qa!`), so a change to the room or the goal
  rules can't silently break verification.

## M15: Vercel Sandbox and the Worker

- **Replays can run in the EU too.** The Sandbox SDK takes a `region`, and
  `fra1` (Frankfurt) is one, so the verifier runs next to the EU D1
  database rather than in the default `iad1`.
- **The Sandbox SDK works on workerd**, streaming calls included. Under
  `wrangler dev` with `nodejs_compat`, a Worker resumed the snapshot, wrote
  the jobs, ran the harness and read its output: 9 of 9 jobs verified in
  about 2.3 s. The bundle is 539 KiB gzipped, under the free plan's limit.
- **All 66 reference solutions verify in the Sandbox** (`fra1`, 1 vCPU):
  about 1 s to resume the snapshot and under 2 s for the replays, so about
  3.5 s for the batch. `curl` from inside the VM fails to resolve a host,
  and `run-batch` now fails outright if the VM can reach the network.
- **CPU on the free plan (measured 2026-10-30).** A throwaway Worker ran 30
  batches of 9 jobs, and `wrangler tail` reported its CPU time. The first 5,
  spaced apart, used 34-81 ms; the next 25, back to back, had a median of
  12 ms (8-64 ms). 23 of the 30 went over the documented 10 ms, yet all 30
  finished with outcome `ok`, so the limit wasn't enforced per request at
  this volume. That is an observation, not a guarantee. The likely reading
  is that the expensive runs are cold starts (loading the 539 KiB bundle),
  which is what a once-a-minute cron would mostly see. So M18 must treat a
  killed run as normal (pending runs stay pending and are retried), and watch
  for `exceededCpu`. If it shows up, the options remain the REST API with
  `fetch` and a smaller bundle, or the $5 Workers plan.
- **The snapshot** pins Neovim 0.12.6 by the SHA-256 of each Linux build,
  holds vimdojo's Lua and the bundled `cli.js`, and has its network denied
  before it's saved. It never expires; it's rebuilt when the room's Lua, the
  goal rules or the harness change.
- **Not yet:** the uid split between the harness and the replayed Neovim
  (the spike runs both as the sandbox's default user). It comes with the
  production verifier in M18.

## M16: level identity and key logs

- **Level hash:** SHA-256 of canonical JSON (sorted keys, no spaces) over the
  text or files, cursor start, goal, options, presets and `requires`. Copy and
  par edits keep a level's board. Fractional numbers are refused rather than
  formatted, because no level needs them and Lua and JavaScript print them
  differently. The fixture's hashes come from Python, so the two ports can't
  agree on a shared mistake.
- **The manifest is committed** (`verifier/manifest.json`), not generated at
  build time as PLAN-v3 first said. A change that resets a board then shows up
  in the pull request's diff, and both test suites fail until `make manifest`
  is run. It's generated in Lua so level authors don't need Node. It can't live
  in `challenges/`, because the plugin loads every JSON file there as a pack.
- **Only rankable runs are kept:** a clean config, no paste, not Setup. Keeping
  anything else would risk a run that can't rank replacing the one that can.
- **Each level keeps its best run**, in its own file under `stdpath("state")`,
  never in the shareable `progress.json`. A tie keeps the earlier run, because
  boards rank the first to reach a count ahead. A run on a new level hash
  replaces any older one, whatever its keys, since that board is gone.
- **Why a paste can't be logged:** bracketed paste inserts text even in Normal
  mode, which typing the same keys wouldn't do, so no replay would reproduce it.
- **Keys are spelled the same on every Neovim.** `keytrans()` returns `|` and
  `\\` on 0.12 but `<Bar>` and `<Bslash>` on nightly (CI caught it). Both replay
  fine, but the server caches verdicts by key log, so the plugin normalizes them.
- **Gaps are computed from rounded absolute times**, so 1,000 quick keys can't
  drift, and a removed control key's time goes with it.
- **Proof:** `check-keylogs` plays all 66 ranked levels through the live room,
  then replays the files the plugin wrote in the M15 harness. Every count
  matches the game's claim and every hash matches the manifest.
