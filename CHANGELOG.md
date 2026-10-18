# Changelog

## Unreleased

### Added

- **Usage track:** 13 levels in three packs (Windows and Buffers,
  Project-Wide Edits, Neovim Built-ins), played in a real workspace of files.
- **Setup-track engine** (M12): levels where you edit an `init.lua` checked by
  behavior probes in a sandboxed Neovim. The curriculum is still to come.
- **For authors:** workspace `files` with `open`, `preset.commands`, and the
  `files_equal`, `layout` and `config_probes` goals.

### Fixed

- `<C-^>` and other modifier + punctuation keys count as one key.

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
