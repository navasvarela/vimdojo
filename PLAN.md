# Vim Motions Game: MVP Plan

> Working name: **vimdojo** (placeholder, rename freely).
> This document is the brief for Claude Code. Read it fully before writing code, then work milestone by milestone, committing after each one.

## 1. Goal

A text-based game that teaches Vim motions through short puzzles. The player gets a piece of text and a goal (e.g. "delete the typo", "put the cursor on the last word") and must solve it using Vim keystrokes. Each attempt is scored on time, keystroke count, and a per-level par.

The project has two deliverables sharing one set of challenge data:

1. **Neovim plugin** (Lua): the real game, running in real Neovim.
2. **Static web page** on GitHub Pages: marketing/presentation material plus a playable demo (a handful of levels) using a browser Vim emulation.

**Hard constraint: zero hosting cost.** No backend, no database, no accounts. Everything is local files, `localStorage`, or static hosting.

## 2. Non-goals for the MVP

- Neovim configuration/setup challenges (planned for v2, see section 10)
- Accounts, leaderboards, or any server
- Server-side replay verification
- Macros, registers, marks, ex commands (later curriculum levels)
- Mobile-friendly web gameplay (the landing page should look fine on mobile, but the demo can require a physical keyboard)

## 3. Repository layout

Monorepo:

```
vimdojo/
├── PLAN.md
├── README.md
├── challenges/                  # SHARED data, single source of truth
│   ├── schema.json              # JSON Schema for a challenge file
│   ├── 01-basic-motions.json    # one file per "pack" (a group of levels)
│   ├── 02-find-and-till.json
│   └── ...
├── plugin/
│   └── vimdojo.lua              # defines :VimDojo user command (thin)
├── lua/vimdojo/
│   ├── init.lua                 # setup(opts), public API
│   ├── challenges.lua           # load + validate challenge JSON
│   ├── game.lua                 # session state machine
│   ├── goals.lua                # goal checkers (buffer_equals, cursor_at, ...)
│   ├── keys.lua                 # keystroke capture and counting
│   ├── scoring.lua              # score and star computation
│   ├── storage.lua              # progress persistence (JSON file)
│   └── ui.lua                   # scratch buffer, floating windows, menus
├── tests/
│   ├── minimal_init.lua
│   ├── goals_spec.lua
│   ├── scoring_spec.lua
│   ├── storage_spec.lua
│   └── solutions_spec.lua       # runs every challenge's reference solution
├── web/
│   ├── package.json
│   ├── vite.config.ts           # set `base` for GH Pages (/<repo-name>/)
│   ├── index.html
│   └── src/
│       ├── main.ts
│       ├── landing/             # marketing sections
│       ├── game/                # demo game (CodeMirror + vim)
│       ├── goals.ts             # TS port of goal checkers
│       ├── scoring.ts           # TS port of scoring (must match Lua)
│       └── storage.ts           # localStorage progress
└── .github/workflows/
    ├── ci.yml                   # lint + plugin tests + web build
    └── pages.yml                # deploy web/ to GitHub Pages
```

The `web/` build should read `../challenges/*.json` at build time (Vite JSON import or a copy step), so there is never a second copy of the data.

## 4. Shared challenge schema

JSON, not YAML, because Neovim can decode JSON natively (`vim.json.decode`) and has no YAML parser.

A pack file:

```json
{
  "pack": "basic-motions",
  "title": "Basic Motions",
  "order": 1,
  "levels": [
    {
      "id": "basic-motions-03",
      "title": "Kill the typo",
      "description": "Remove the stray word 'fxo' so the sentence reads correctly.",
      "start_text": ["The quick brown fxo jumps"],
      "cursor_start": [1, 0],
      "goal": { "type": "buffer_equals", "value": ["The quick brown jumps"] },
      "par_keys": 6,
      "par_seconds": 10,
      "hint": "Try f then dw.",
      "solution": "fxdw",
      "teaches": ["f", "dw"],
      "web_demo": true
    }
  ]
}
```

Field notes:

- `start_text` and goal `value` are **arrays of lines** (avoids newline ambiguity across Lua and JS).
- `cursor_start` is `[line, col]`, **1-based line, 0-based col** (matches `nvim_win_get_cursor`). Document this in `schema.json` and convert in the web port.
- `solution` is a reference keystroke string, used only by tests to prove each level is solvable (see section 8). It is never shown to the player.
- `web_demo: true` marks levels that are included in the browser demo. Only flag levels that behave identically in the CodeMirror Vim emulation.
- Goal types for the MVP:
  - `buffer_equals`: `{ "type": "buffer_equals", "value": [lines] }`
  - `cursor_at`: `{ "type": "cursor_at", "line": N, "col": N }` (the buffer must also be unchanged unless `allow_edit: true`)
  - Leave room for more (`register_contains`, `mode_is`, etc.) but **do not implement them yet**.
- Write a `challenges/schema.json` (JSON Schema) and validate packs against it in CI.

## 5. Plugin design (Lua, Neovim 0.10+)

### 5.1 User-facing behavior

- `:VimDojo` opens a menu (packs, then levels, showing lock state, best time, best keys, stars).
- Selecting a level opens a **scratch buffer** (`buftype=nofile`, no swap, not modifiable outside the game) in a floating window or dedicated tab, showing:
  - Title and description in a header (extmark virtual lines or a separate small window, so they don't pollute the buffer being edited)
  - Live timer and keystroke counter in a statusline/winbar
  - Par values
- The timer **starts on the first keystroke**, not when the level opens.
- Reaching the goal ends the attempt immediately and shows a results screen: time, keys, par, stars, best-so-far, and buttons/keys for *Next level*, *Retry*, *Menu*.
- `:VimDojo reset` (or similar) restarts the current level; `<Esc><Esc>` or a documented key quits to the menu. Reserve game-control keys carefully and document them. They must not be counted as attempt keystrokes.
- Hint: a documented key shows the level's `hint` and applies a small score penalty (or just marks the attempt as "hinted").

### 5.2 Mechanics

- **Keystroke capture:** `vim.on_key(fn, ns)` with a dedicated namespace; convert with `vim.fn.keytrans()` for readable key names. Only count while a game session is active and the game window is focused. Always remove the callback (`vim.on_key(nil, ns)`) on session end.
- **Counting rule (decide and document):** count each physical key typed (so `d2w` = 3, `<Esc>` = 1). Don't count mouse events. Consider disabling the mouse inside the game buffer (`vim.opt_local.mouse = ""`).
- **Goal checking:** after each keystroke, evaluate the goal on `TextChanged`, `TextChangedI`, and `CursorMoved`/`CursorMovedI` autocmds scoped to the game buffer. Use `vim.schedule` where state must be settled first (on_key fires *before* the key is processed).
- **Timing:** `vim.uv.hrtime()` (fall back to `vim.loop.hrtime()` for older versions if you choose to support 0.9).
- **Scoring (`scoring.lua`):** pure functions, no UI or Neovim API calls, so they're trivially testable and portable to TS.
  - Inputs: `keys`, `seconds`, `par_keys`, `par_seconds`, `hinted`.
  - Output: `stars` 1-3 plus a numeric score.
  - Suggested rule: 3 stars if `keys <= par_keys` and `seconds <= par_seconds`; 2 stars if `keys <= par_keys * 1.5`; otherwise 1 star (completion). Keystrokes weigh more than time, because time alone rewards typing speed rather than Vim skill. Tune later, but keep the function pure and documented.
- **Progression:** a level unlocks when the previous level in the pack is completed (any stars). Pack N+1 unlocks when pack N is complete. Add a `unlock_all = true` option in `setup()` for testing and for experienced users.

### 5.3 Persistence

- File: `vim.fn.stdpath("data") .. "/vimdojo/progress.json"`.
- Shape:
  ```json
  {
    "version": 1,
    "levels": {
      "basic-motions-03": { "best_keys": 5, "best_seconds": 7.4, "stars": 3, "attempts": 4 }
    }
  }
  ```
- Write atomically (write temp file, then rename). Tolerate a missing or corrupt file (start fresh, back up the corrupt one). Include a `version` field for future migrations.

### 5.4 Public API and config

```lua
require("vimdojo").setup({
  unlock_all = false,
  window = "float",   -- "float" | "tab"
  progress_path = nil, -- override for tests
})
```

Compatible with lazy.nvim (`opts = {}` / `cmd = "VimDojo"`), packer, and vim-plug. Keep startup cost near zero: `plugin/vimdojo.lua` only defines the command; everything else is lazy-`require`d.

### 5.5 Dependencies

None at runtime. No telescope/plenary/nui requirement for players. Dev-only: plenary.nvim or mini.test for tests, stylua and luacheck/selene for linting.

## 6. Web design (static site on GitHub Pages)

### 6.1 Stack

- **Vite + TypeScript**, plain DOM or a light framework (Svelte or Preact is fine; keep the bundle small). Avoid heavy frameworks and SSR.
- **CodeMirror 6** + **`@replit/codemirror-vim`** for the demo editor.
- CSS: hand-written or Tailwind. Needs a distinct terminal-flavored aesthetic (monospace, dark theme, restrained accent color). Avoid a generic template look.
- No analytics or third-party trackers in the MVP (keeps it simple and privacy-friendly).

### 6.2 Page structure (single page)

1. **Hero**: name, one-line pitch, an animated looping GIF/SVG or small scripted demo of a level being solved, with CTAs ("Play the demo", "Install the plugin").
2. **How it works**: 3 steps (get a puzzle, solve it with motions, beat par).
3. **Live demo**: the embedded game, using levels flagged `web_demo: true`.
4. **Install**: copy-paste snippets for lazy.nvim, packer, and vim-plug, with a copy button.
5. **Curriculum**: list of packs and what each teaches, with a note on what's coming (config track).
6. **Footer**: GitHub link, license, credits.

### 6.3 Demo game behavior

- Same rules as the plugin: timer starts on first keystroke, key counter, goal check after each change, results card with stars.
- Keystroke counting in the browser: use a CodeMirror keydown handler (capture phase) and ignore modifier-only events. It will differ slightly from Neovim in edge cases; document this and treat the web score as indicative.
- Progress in `localStorage` (try/catch every access; handle storage being unavailable). Add "Export progress / Import progress" as a JSON download/upload, using the **same schema** as the plugin's `progress.json` where practical.
- Show a small banner: "The demo uses a Vim emulation. For the real thing, install the Neovim plugin."
- Keyboard-first UX: visible focus, no mouse needed to restart, advance, or open hints.

### 6.4 Deployment

- `pages.yml` GitHub Action: install, `npm run build` in `web/`, upload `web/dist` with `actions/upload-pages-artifact`, deploy with `actions/deploy-pages`. Configure Pages source to "GitHub Actions".
- Set Vite `base` to `/<repo-name>/` (parameterize it; a custom domain can come later).

## 7. Initial content (MVP curriculum)

Aim for **3 packs, about 15 levels total**, ordered by difficulty. Each level should teach one idea and have a realistic, slightly funny snippet of text (code, prose, or config) rather than "foo bar".

| Pack | Teaches | Levels |
|------|---------|--------|
| 01 Basic motions | `h j k l`, `w b e`, `0 ^ $`, `gg G` | ~5 |
| 02 Find and jump | `f t F T ; ,`, `{ }`, `%`, counts | ~5 |
| 03 Operate | `d c y` + motions, `dd`, `cw`, `.`, `ciw`, `di"`, `dap` | ~5 |

Rules for authoring levels:

- Every level has a `solution` that passes in real Neovim (enforced by tests).
- `par_keys` should equal or be very close to the length of the best known solution.
- Avoid levels with multiple "equivalent" end states that `buffer_equals` would reject unfairly. If a goal is ambiguous, fix the level, not the checker.

## 8. Testing strategy

1. **Unit tests (plugin):** `goals`, `scoring`, `storage` (use temp dirs), `challenges` (loader and validation).
2. **Solution tests (the most valuable ones):** for every level in `challenges/`, open a buffer in headless Neovim, set `start_text` and `cursor_start`, feed the `solution` via `nvim_feedkeys` (or `vim.cmd("normal ...")`), and assert the goal is satisfied and `#solution keys <= par_keys`. This guarantees every level is solvable and par is honest.
3. **Schema validation in CI:** validate all pack files against `challenges/schema.json`.
4. **Web:** unit-test `goals.ts` and `scoring.ts` with the **same fixtures** as the Lua tests (a shared `tests/fixtures/*.json` is a nice touch to keep both ports in sync). A Playwright smoke test of the demo (load page, solve one level via keyboard, see the results card) is a stretch goal.
5. **Run in CI:** GitHub Actions matrix over Neovim stable and nightly (e.g. via `rhysd/action-setup-vim`), `stylua --check`, `luacheck`/`selene`, `npm ci && npm run build && npm test`.

## 9. Milestones

Work in order. Each milestone must end in a working, committed state with passing tests.

**M0, Scaffolding**
- Repo structure, README stub, license (MIT unless told otherwise), `.gitignore`, `stylua.toml`, linter config.
- `challenges/schema.json` plus 3 sample levels.
- CI running lint plus an empty test suite.
- *Done when:* CI is green.

**M1, Plugin core (no UI polish)**
- `challenges.lua`, `goals.lua`, `scoring.lua`, `storage.lua` with unit tests.
- `solutions_spec` running against the sample levels.
- *Done when:* `make test` (or equivalent) passes locally and in CI.

**M2, Playable plugin loop**
- `:VimDojo` opens a level in a scratch buffer, key capture and timer work, goal detection ends the attempt, results screen shows, progress saves.
- Basic level-select menu with lock state.
- *Done when:* a human can play levels 1-3 end to end in Neovim and best scores persist across restarts.

**M3, Content**
- Author all ~15 levels across 3 packs with solutions and pars. Solution tests pass for every one.
- Hint support and reset/quit keys.
- *Done when:* all 3 packs are completable and the whole suite is green.

**M4, Web demo**
- Vite + TS project; CodeMirror Vim editor; TS goal and scoring ports; localStorage progress; results card.
- Mark which levels are `web_demo` after manually checking each in the emulation.
- *Done when:* the demo is playable locally with `npm run dev` and TS tests pass against the shared fixtures.

**M5, Landing page and deploy**
- All page sections from 6.2, responsive layout, install snippets with copy buttons.
- `pages.yml` deployment; verify the live URL works with the correct `base` path.
- *Done when:* the site is live on GitHub Pages.

**M6, Release polish**
- README with GIF, install instructions, level-authoring guide (so others can contribute packs), `CONTRIBUTING.md`.
- Tag `v0.1.0`; add `doc/vimdojo.txt` vimdoc help file.

## 10. Roadmap after the MVP (do not build now)

- **Neovim setup track:** challenges like "make `<leader>w` save the file" or "enable relative line numbers". The player edits a small Lua snippet; the game loads it in a sandboxed `nvim --headless -u` child process and asserts on resulting options/keymaps (`vim.o.relativenumber`, `vim.fn.maparg`). Must be sandboxed and must never run on a shared server.
- More goal types and a harder curriculum: visual mode, search, registers, marks, macros, `:s`.
- Daily challenge; export/share a result as text.
- Optional leaderboard via a free-tier backend, only if there is demand.

## 11. Working agreements for Claude Code

- **Ask before deviating** from this plan on architecture choices; small implementation decisions are yours to make, and note them in commit messages.
- Prefer small, pure, tested modules over large files. Scoring and goal logic must have no UI dependencies.
- Keep the plugin dependency-free at runtime.
- Never duplicate challenge data. `challenges/` is the single source of truth.
- Commit per milestone (or finer). Keep a running `docs/decisions.md` with short notes on decisions made (key-counting rule, star thresholds, cursor coordinate convention, etc.).
- When something in this plan turns out to be wrong or impractical (e.g. a Vim feature the emulation can't reproduce), flag it and propose an alternative instead of silently working around it.
- Start now with **M0**.
