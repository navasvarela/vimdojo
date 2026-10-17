# vimdojo v2 plan: advanced motions, Neovim usage, Neovim setup

> Follows [PLAN.md](PLAN.md) (the MVP, shipped as v0.1.0). Same working
> agreements apply: milestone by milestone, tests first-class, decisions logged
> in `docs/decisions.md`, ask before deviating on architecture.

## 1. Goal

Grow vimdojo from "basic motions" into three tracks:

| Track | What it teaches | Where it runs |
|---|---|---|
| **Motions** (existing + advanced) | Editing language: visual mode, search, text objects, registers, macros, Ex commands | Neovim; web demo where the emulation matches |
| **Usage** (new) | Working in Neovim: windows, buffers, quickfix, project-wide edits, built-in defaults | Neovim only |
| **Setup** (new) | Configuring Neovim in Lua: options, keymaps, autocommands, user commands, debugging configs, modern 0.11+ APIs | Neovim only, in a sandboxed child process |

Each track has its own packs and its own progression.

### Non-goals (still)

- No server, accounts or leaderboards. Zero hosting cost stays a hard
  constraint.
- No plugin-manager or network-dependent challenges (installing plugins,
  real LSP servers).
- No arbitrary user Lua runs anywhere except the player's own machine.

## 2. What we verified before planning

These were measured in Neovim 0.12, not assumed:

| Question | Result | Consequence |
|---|---|---|
| Are keys replayed by a macro counted? | No. `3@a` counts 3 typed keys; the replayed keys arrive with an empty `typed`. | Macro levels work with today's counting rule. Recording counts and replay is free, which is exactly the lesson. |
| Are command-line keys counted? | Yes. `:%s/\d/N/<CR>` counts 10. | Ex levels work as-is. Tab-completion counts as 1 key, which rewards using it. |
| Can the game host a clean child Neovim and observe it? | Yes. `nvim --clean --listen <sock>` in a `:terminal` receives the player's keys, the parent's `on_key` still counts them, and an RPC round trip to read child state takes **~0.04 ms**. | A "clean room" engine is feasible (decision D1). |

## 3. The key architectural decision (D1): a clean-room engine (chosen)

Advanced levels touch global state the MVP never had to: registers, marks,
search history, `ignorecase`/`gdefault`/`wrapscan`, window layouts, the
working directory and real files. Players' configs also interfere more: an
autopairs plugin breaks par on `ci"`, completion menus eat `<C-n>`, a remapped
`n` breaks search levels.

**Option A (recommended): run every level in a child `nvim --clean`** inside a
terminal window. The parent keeps the chrome: header float, winbar timer and
results card.

- Keys go to the child. The parent counts them with `on_key` (proven) and
  reads child state over RPC. The child pushes goal checks with `rpcnotify`
  from its own autocmds, so the game doesn't poll.
- Isolation comes free. Registers, marks, options, mappings, cwd, windows and
  history all live in a throwaway process. There's no save/restore code, and
  nothing a level does can damage the player's session.
- It is deterministic: every level runs against stock defaults, the same ones
  the solution tests use.
- `config = "clean" | "mine"` lets players opt into their own config (the
  child loads `$MYVIMRC`). Scores in "mine" mode are marked as such.
- Costs: terminal-in-terminal quirks (Alt keys, colors), `<C-\><C-n>` is
  reserved by the terminal, and a real rewrite of `app.lua`/`ui.lua`. Windows
  needs named pipes for `--listen`; Neovim supports them, but this is untested.

**Option B: stay in-process and add isolation.** Save and restore registers,
`@/`, marks and global options, and use a dedicated tab for multi-window
levels. This is less work up front, but every new feature needs more
isolation code, and user plugins keep interfering.

Chosen: A (see §7).

## 4. Curriculum

Par rule unchanged: the shortest solution that uses only what the track has
taught so far. Level ideas are sketches; exact text, pars and solutions are
settled during authoring and proven by the solution tests.

### Track: Motions (advanced). Packs 04-10, about 44 levels.

**04 Visual Mode**

| # | Title | Teaches | Goal | Idea |
|---|---|---|---|---|
| 1 | Highlight reel | `v` + operator | buffer | Delete a phrase that spans punctuation: `vt.d` |
| 2 | Line it up | `V`, `>` | buffer | Indent a 3-line block (`shiftwidth=2` set by the level) |
| 3 | Column of shame | `<C-v>`, `I` | buffer | Prefix four lines with `// ` in one go |
| 4 | Ragged edge | `<C-v>$A` | buffer | Append `;` to lines of different lengths |
| 5 | The other end | `o` | buffer | Grow a selection backwards, then delete |
| 6 | Block party | `<C-v>c` | buffer | Rename a column of values in an aligned table |

**05 Search**

| # | Title | Teaches | Goal | Idea |
|---|---|---|---|---|
| 1 | Needle, haystack | `/` | cursor | Find a word in a 30-line log. A shorter unique pattern beats par. |
| 2 | Next! | `n`, `N` | cursor | The 4th `ERROR` in the log |
| 3 | Under the cursor | `*`, `#` | cursor | Next use of the variable under the cursor |
| 4 | Whole words only | `\<\>` | cursor | Find `id` without stopping on `idea` or `valid` |
| 5 | Change gang | `cgn`, `.` | buffer | Rename 3 of 4 occurrences, skipping one with `n` |
| 6 | Land on the end | `/pat/e` | cursor | Search offset to the end of a match |

**06 Text Objects**

| # | Title | Teaches | Goal | Idea |
|---|---|---|---|---|
| 1 | Argument clinic | `ci(` | buffer | Replace a function's arguments |
| 2 | Empty the bins | `di[` | buffer | Clear an array literal |
| 3 | Tag, you're it | `cit` | buffer | Change HTML element text |
| 4 | Clean cut | `daw` | buffer | Delete a word *and* its space (vs `diw`) |
| 5 | Copy the body | `yi{`, `p` | buffer | Duplicate a block's contents |
| 6 | One sentence too many | `das` | buffer | Delete a sentence from a paragraph |

**07 Transform**

| # | Title | Teaches | Goal | Idea |
|---|---|---|---|---|
| 1 | Caps lock | `gUiw` | buffer | `max_retries` to `MAX_RETRIES` |
| 2 | Version bump | `<C-a>` | buffer | `v1.9.9` to `v1.9.10` (it's not string math) |
| 3 | Count me in | `g<C-a>` | buffer | Turn `1. 1. 1. 1.` into `1. 2. 3. 4.` |
| 4 | Join the club | `J`, `gJ` | buffer | Join wrapped lines with and without spaces |
| 5 | Teh typo | `xp`, `ddp` | buffer | Swap characters and lines |
| 6 | Replace mode | `r`, `R` | buffer | Overwrite a fixed-width field |

**08 Registers**

| # | Title | Teaches | Goal | Idea |
|---|---|---|---|---|
| 1 | Where did my yank go? | `"0p` | buffer | Paste the yank after a delete clobbered `"` |
| 2 | Named and saved | `"ay`, `"ap` | buffer | Carry a line past other edits |
| 3 | Collector | `"Ay` | buffer | Append several lines to one register, paste them all |
| 4 | Into the void | `"_d` | buffer | Delete without losing what you yanked |
| 5 | Paste while typing | `<C-r>a` | buffer | Insert a register's content mid-sentence |
| 6 | Calculator | `<C-r>=` | buffer | Write the result of `12*37` into the text |

**09 Macros**

| # | Title | Teaches | Goal | Idea |
|---|---|---|---|---|
| 1 | Record and replay | `qa`, `@a` | buffer | Same edit on 6 lines. A macro beats manual par. |
| 2 | Again and again | `@@`, `N@a` | buffer | 25 lines, where the count makes it cheap |
| 3 | CSV to Lua | macro | buffer | `alice,31` to `{ name = "alice", age = 31 },` |
| 4 | Until it stops | failing search ends macro | buffer | `999@a` safely stops at the last match (needs `nowrapscan`) |
| 5 | Only where it matters | `:g/pat/norm @a` | buffer | Apply a macro to matching lines only |
| 6 | Numbered list | macro + `<C-a>` | buffer | Generate `item 1` to `item 10` |

**10 Ex Power**

| # | Title | Teaches | Goal | Idea |
|---|---|---|---|---|
| 1 | Find and replace | `:s///g` | buffer | One line, every occurrence |
| 2 | Some, not all | `:%s///gc` | buffer | Confirm-replace selectively (`y`/`n` count as keys) |
| 3 | Swap names | `\v`, groups | buffer | `Lovelace Ada` to `Ada Lovelace` across lines |
| 4 | Silence the logs | `:g//d` | buffer | Delete every `console.log` line |
| 5 | Tidy imports | `:sort u` | buffer | Sort and dedupe an import block |
| 6 | Semicolons everywhere | `:%norm A;` | buffer | Run a Normal command on every line |
| 7 | Move it | `:m`, `:t` | buffer | Move a function above another by line range |

### Track: Usage. Packs 11-13, about 18 levels. Clean room needed.

These levels can start with **several files** in a temp workspace and check
window layouts.

**11 Windows and Buffers** (new goal: `layout`)

| # | Title | Teaches | Idea |
|---|---|---|---|
| 1 | Side by side | `<C-w>v` | Split vertically |
| 2 | Open on the right | `:vs file` | `main.lua` left, `util.lua` right |
| 3 | Swap seats | `<C-w>x` | Exchange two windows |
| 4 | Back and forth | `<C-^>` | Alternate between two buffers to end on a given one |
| 5 | Declutter | `<C-w>o` | Close every other window |
| 6 | Far right | `<C-w>L` | Move a window to the far right |

**12 Project-Wide Edits** (new goal: `files_equal`; real files in a temp dir)

| # | Title | Teaches | Idea |
|---|---|---|---|
| 1 | Follow the path | `gf` | Open the required file and fix a line there |
| 2 | Every TODO | `:vimgrep`, `:copen` | Land on the 3rd TODO across files |
| 3 | Rename everywhere | `:cdo s///` | `getUser` to `fetchUser` in 3 files |
| 4 | Header for all | `:argdo` | Add a license line to every file |
| 5 | Deep find | `:find`, `**` | Open a nested file by name |
| 6 | Global marks | `mA`, `'A` | Jump between files with file marks |

**13 Neovim Built-ins** (`requires` a minimum Neovim version per level)

| # | Title | Teaches | Idea |
|---|---|---|---|
| 1 | Comment out | `gcc`, `gc` (0.10) | Comment a block without plugins |
| 2 | Quickfix hopping | `]q`, `[q` (0.11) | Navigate a preloaded quickfix list |
| 3 | Breathing room | `]<Space>` (0.11) | Add blank lines around a block |
| 4 | Replay | `Q` | Re-run the last recorded macro |
| 5 | Again, everywhere | `g&` | Repeat the last `:s` on the whole file |
| 6 | Fix the error | `]d` (0.10) | Jump to a preset diagnostic and fix the line |

### Track: Setup. Packs 14-17, about 20 levels. Sandboxed checks.

The player edits an `init.lua` buffer (it starts from a starter snippet).
The goal is a set of **behavior probes** run against that config in a
sandboxed child Neovim. Probes check what the config *does*, not how it's
written, so `vim.keymap.set(...)` and `nnoremap ...` both pass.

**14 Options and Keymaps**

| # | Title | Probe |
|---|---|---|
| 1 | Relative thinking | `relativenumber` is on |
| 2 | Space leader | `mapleader == " "`, set before any mapping |
| 3 | Save shortcut | `<leader>w` writes a modified buffer |
| 4 | Two spaces | `>>` on a line indents by 2 spaces (`expandtab`, `shiftwidth`) |
| 5 | Smart search | `/foo` matches `Foo`, `/Foo` doesn't match `foo` |
| 6 | Stay centered | after `<C-d>`, the cursor sits mid-window |
| 7 | Clear the glare | `<Esc>` in Normal mode turns off search highlighting |

**15 Autocommands and Commands**

| # | Title | Probe |
|---|---|---|
| 1 | Flash the yank | yanking creates a highlight extmark (`vim.hl.on_yank`) |
| 2 | Python is different | a `python` buffer gets `shiftwidth=4` and `expandtab` |
| 3 | `:Trim` | the user command strips trailing whitespace from a fixture |
| 4 | Trim on save | `BufWritePre` trims automatically |
| 5 | Source it twice | re-sourcing the config doesn't duplicate autocmds (augroup with `clear = true`) |

**16 Fix the Broken Config** (the starter snippet has a bug)

| # | Title | The bug |
|---|---|---|
| 1 | Leader too late | `mapleader` set after the mappings that use it |
| 2 | Type error | `vim.opt.shiftwidth = "2"` |
| 3 | Missing enter | `":w"` rhs without `<CR>` |
| 4 | Ghost autocmds | autocmd without a group, so it stacks on re-source |
| 5 | `vim.o` vs `vim.opt` | table assigned through `vim.o` |

**17 Modern Neovim** (`requires` 0.11+)

| # | Title | Probe |
|---|---|---|
| 1 | Speak up, diagnostics | `vim.diagnostic.config` turns `virtual_text` back on |
| 2 | Rounded everywhere | `winborder = "rounded"` |
| 3 | LSP, the new way | `vim.lsp.config("*", { root_markers = { ".git" } })` is set (no server needed) |
| 4 | Treesitter on | Lua buffers start Treesitter highlighting (bundled parser) |

## 5. Engine and data changes

### 5.1 Schema v2 (backwards compatible)

- **Pack**: `track` (`"motions" | "usage" | "setup"`, default `"motions"`).
- **Level**:
  - `requires`: `{ "nvim": "0.11" }`. The menu shows unsupported levels as
    "needs Neovim 0.11", and the solution tests skip them on older versions.
  - `options`: options the level sets in its sandbox (`shiftwidth`,
    `textwidth`, `wrapscan` ...).
  - `files`: `{ "path": [lines] }` for multi-file levels (replaces
    `start_text`), plus `open` to say which file starts focused.
  - `preset`: state applied before the timer starts (registers, marks,
    quickfix list, diagnostics).
- **Goals** (one kind table in Lua and one in TS, as today):
  - `all_of`: `[goal, ...]` for composite goals.
  - `register_contains`: `{ register, value }`.
  - `files_equal`: `{ "path": [lines] }`, checked against buffer contents
    (saving isn't required).
  - `layout`: an expected `winlayout()` shape with the file shown in each
    window.
  - `config_probes`: setup track (§5.3).
- Everything new is added to `schema.json`, both validators and the shared
  fixtures.

### 5.2 Clean-room host (D1 = A)

- `lua/vimdojo/room.lua` spawns `nvim --clean --listen <sock>` in a
  `:terminal` (env: temp `XDG_*`, `NVIM_APPNAME=vimdojo-room`) with a small
  bootstrap init that:
  1. builds the level from JSON: buffers or workspace files, options,
     presets;
  2. installs autocmds that `rpcnotify` the parent on
     `TextChanged`/`CursorMoved`/`ModeChanged`/`WinEnter`/`BufEnter`;
  3. maps game controls (hint, reset, quit) to `rpcnotify`, so the child
     never sees them as edits.
- The parent counts keys with `on_key` while the room window is focused, as
  today, and evaluates goals by snapshotting child state over RPC.
- **Solution tests run through the same room**, so a level is proven in
  exactly the environment players get.
- The existing in-process engine is removed once the 20 MVP levels pass in
  the room.

### 5.3 Setup-track sandbox

- On each change, debounced (~400 ms) after the buffer settles in Normal
  mode, the parent writes the player's `init.lua` to a temp dir and runs
  `vim.system({ nvim, "--headless", "--clean", "-n", "-i", "NONE", "-u",
  init, "-l", probe_runner, probes.json })` with temp `XDG_*` dirs and a 3 s
  timeout. Results come back as JSON. The game completes when every probe
  passes **and** the config loaded without errors.
- Probes are declarative data, implemented once in
  `lua/vimdojo/probes/`:
  - `option`
  - `keys` (feed keys in a fixture buffer, then assert on the buffer,
    cursor, `modified`, `v:hlsearch` or windows)
  - `filetype` (open a buffer of that type, then assert on its options)
  - `command` (run on fixture lines, compare)
  - `source_twice` (count autocmds)
  - `extmarks_after` (for yank highlight)
  - `lua` escape hatch, reviewed in PRs
- This is isolation, not a security sandbox. The code is the player's own,
  on their own machine. The point is that it never touches their real
  config, data or session.
- Par: the reference solution is a keystroke edit of the starter snippet,
  proven by the solution tests like any other level (decision D2).

### 5.4 Tooling

- `make par` grows search (`/x<CR>`, `n`, `*`) and visual-mode tokens for
  cursor levels.
- The emulation gate in the web tests flags advanced Motions levels for the
  demo automatically. Usage and Setup levels never get `web_demo`.
- The level-authoring guide gets sections for multi-file levels, presets and
  probes.

### 5.5 Web and landing

- The landing page shows the curriculum by track, with a "Neovim only" badge
  on Usage and Setup.
- The demo adds the advanced Motions levels that pass the emulation gate
  (codemirror-vim supports macros, registers and `:s`; some visual-block and
  `gn` cases may not pass).

## 6. Milestones

| Milestone | Scope | Done when |
|---|---|---|
| **M7 Clean room** | `room.lua`, RPC observer, controls, key counting, results flow; port the 20 MVP levels; solution tests run in the room | All existing levels play and pass tests in the room; in-process engine removed |
| **M8 Schema v2** | `track`, `requires`, `options`, `preset`, `files`; goals `all_of`, `register_contains`; menu grouped by track with independent progression; TS port and fixtures | Schema, Lua and TS agree on shared fixtures; CI green |
| **M9 Motions wave 1** | Packs 04-07 (Visual, Search, Text Objects, Transform), ~24 levels; `make par` search/visual tokens | All solutions pass; pars match the par finder where applicable |
| **M10 Motions wave 2** | Packs 08-10 (Registers, Macros, Ex), ~19 levels. **Release v0.2.0** | Same, plus LuaRocks release |
| **M11 Usage track** | Workspace files, `files_equal`, `layout`, version-gated levels; packs 11-13. **Release v0.3.0** | Multi-file and window levels proven in the room |
| **M12 Setup engine** | Sandbox runner, probe library, async debounced checks, config solution tests | A sample config level completes end to end; probes unit-tested |
| **M13 Setup content** | Packs 14-17, ~20 levels. **Release v0.4.0** | All setup solutions pass every probe on stable and nightly |
| **M14 Web refresh** | Tracks on the landing page, new demo levels, badges | Deployed |

M9-M10 (content) and M12 (engine) don't touch the same files, so they can
run in parallel once M8 lands.

## 7. Decisions (agreed 2026-10-17)

| # | Decision | Chosen |
|---|---|---|
| D1 | Engine | **Clean room**: every level runs in a child `nvim --clean`, with `config = "mine"` as an opt-in |
| D2 | Setup-track scoring | **Keystroke par**: a reference edit of the starter snippet, proven by the solution tests |
| D3 | Progression | **Independent tracks**: each track's first pack is unlocked from the start |
| D4 | Minimum Neovim | **0.10**, with per-level `requires` for newer features |

## 8. Risks

- **Terminal quirks in the clean room.** Alt keys, colors and `<C-\><C-n>`
  differ across terminals. Mitigation: control keys go through child-side
  mappings, not terminal tricks; manual check on kitty, iTerm2, WezTerm and
  Windows Terminal before v0.2.0.
- **Windows support.** `--listen` named pipes and `:terminal` behave
  differently there. Mitigation: add a Windows runner to the CI matrix in M7.
- **Probe brittleness across Neovim versions.** For example,
  `vim.highlight` was renamed to `vim.hl` and the yank-highlight namespace
  name changed. Mitigation: behavior-level probes, `requires` gates, and
  nightly in CI.
- **Par honesty for long Ex and Setup solutions.** Typing-heavy pars are less
  interesting. Mitigation: generous `par_seconds`, and keystroke pars based
  on the reference edit.
- **Scope.** About 80 new levels. Mitigation: ship by wave (v0.2, v0.3,
  v0.4); every wave is useful on its own.
