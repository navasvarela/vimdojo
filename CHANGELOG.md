# Changelog

## Unreleased

### Added

- **Setup track:** 18 levels in four packs (Options and Keymaps,
  Autocommands and Commands, Fix the Broken Config, Modern Neovim), where you
  edit an `init.lua` and behavior probes check what it does. Modern Neovim
  needs 0.11.
- CI runs the plugin tests on Neovim 0.10.4 too.

### Fixed

- Packs no longer fail to load on Neovim 0.10 because a 0.11-only level
  names a 0.11 option.

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
