# Changelog

## v0.6.0 (2026-10-31)

### Added

- **Leaderboards, right in Neovim.** Optional and off by default: set
  `online = { enabled = true }`, then `:VimDojo login`. `s` on the results card
  submits a run, a server replays it in a clean Neovim and recounts the keys, and the
  verdict and your place show up in a few seconds. `b` on the results card or
  `:VimDojo board [level]` shows a level's board, and `:VimDojo scores` shows your
  bests, places and anything you haven't sent. `:VimDojo submit` sends everything
  you've played.
- Boards rank by verified keys, then by who got there first, and show handles and
  counts only. Your keys are the level's solution, so they stay private. Setup levels
  aren't ranked.
- **On the site:** [leaderboards](https://vimdojo.org/boards/), public profiles, an
  [account page](https://vimdojo.org/account/) to manage logins, export or delete your
  data, and a [privacy page](https://vimdojo.org/privacy/).
- The plugin keeps your best run per level in `stdpath("state")/vimdojo/keylogs`, which
  stays on your machine unless you submit it.
- A [security policy](https://github.com/navasvarela/vimdojo/blob/main/SECURITY.md).

### Changed

- Without a connection, a submitted run waits, and is sent the next time you use an
  online command.
- The site's footer now says it sets no cookies unless you sign in.

## v0.5.0 (2026-10-30)

### Added

- **Daily challenge:** one level a day, the same for everyone, in the plugin
  and on https://vimdojo.org. It sits at the top of the menu, or run
  `:VimDojo daily`. It's picked from the date (UTC) with no network access,
  plays every demo level once before any repeats, and ignores pack locks.
- **Share your result:** `y` on the results card (Copy result on the site)
  copies a spoiler-free line such as
  `vimdojo daily 2026-10-30 ★★★ 7 keys (par 7) 4.3s` with the site link. It
  gives your score, never your keys.
- **Community:** GitHub Discussions for level ideas, dailies and beaten pars,
  linked from the README and the site.
- **For authors:** an optional `authors` field (GitHub handles) on packs and
  levels, credited on the site; a pull request template with the level review
  checklist; and a licensing note in CONTRIBUTING.
- The site lists the curriculum by track, with a "Neovim only" badge on Usage
  and Setup, and now lives at https://vimdojo.org.

### Fixed

- Pasted text now costs what typing it would (one key per character), in the
  plugin and the browser demo. Before, pasting a solution cost no keys.

## v0.4.0 (2026-10-19)

### Added

- **Setup track:** 18 levels in four packs (Options and Keymaps,
  Autocommands and Commands, Fix the Broken Config, Modern Neovim). You edit
  an `init.lua`; the game runs it in a sandboxed Neovim and shows inline,
  as you type, which checks still fail. Modern Neovim needs 0.11. All three
  tracks are complete: 84 levels.
- CI runs the plugin tests on Neovim 0.10.4, the oldest supported release,
  as well as stable, nightly and Windows.

### Fixed

- Packs no longer fail to load on Neovim 0.10 because a 0.11-only level
  names a 0.11 option.
- The yank-highlight check works on Neovim 0.10.

## v0.3.0 (2026-10-19)

### Added

- **Usage track:** 13 levels in three packs (Windows and Buffers,
  Project-Wide Edits, Neovim Built-ins), played in a real workspace of files:
  splits, the alternate file, `gf`, `:find`, `:vimgrep` with `:cdo`, `gc`,
  `g&`, `]q` and `]d`. 66 levels in total. The quickfix level needs
  Neovim 0.11.
- **Setup-track engine:** levels where you edit an `init.lua` that behavior
  probes check in a sandboxed Neovim. The Setup curriculum comes in a later
  release.
- **For authors:** workspace `files` with `open`, `preset.commands`, and the
  `files_equal`, `layout` and `config_probes` goals. Failing solution tests
  print the level's `:messages`.

### Fixed

- `<C-^>` and other modifier + punctuation keys count as one key.
- Windows: quitting Neovim mid-level no longer leaves the level's Neovim
  running.

## v0.2.0 (2026-10-18)

### Added

- **33 new levels in six packs:** Visual Mode, Search, Text Objects,
  Transform, Registers and Macros, and Ex Power (53 levels in total).
- **Clean-room engine:** every level runs in its own `nvim --clean` inside a
  terminal window, so your registers, windows and settings are never touched
  and plugins can't interfere with par. `config = "mine"` plays with your own
  config instead.
- **Tracks and version gates:** the menu groups packs by track, and levels
  that need a newer Neovim are labelled instead of blocking progress.
- **New goal types and level features** for authors: `register_contains`,
  `all_of`, level `options`, and register/mark `preset`s
  (see `docs/authoring-levels.md`).
- `challenges_dir` setup option for playing your own packs.
- **Web demo:** 19 levels (was 9). The emulation gate now presses real keys
  in Chromium.
- Logo.

### Changed

- Your Terminal-mode mappings are suspended while a level is open (and
  restored afterwards), so keys like `<Esc>` always reach the level.

## v0.1.0 (2026-10-17)

First release: 20 levels in three packs (Basic Motions, Find and Jump,
Operate), scoring against par, hints, progress saved across sessions, a
browser demo, and `:help vimdojo`.
