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
