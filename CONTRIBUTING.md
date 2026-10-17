# Contributing

Thanks for helping! New levels are the most valuable contribution. Start with
[docs/authoring-levels.md](docs/authoring-levels.md).

## Setup

You need Neovim 0.10+, `make`, `git`, [stylua](https://github.com/JohnnyMorganz/StyLua),
[selene](https://github.com/Kampfkarren/selene) and Node.js 22 for the web demo.

```sh
make deps   # clones plenary.nvim into .deps/ (dev only)
make all    # lint, schema validation, help-file check, plugin tests
```

Web demo:

```sh
cd web
npm install
npx playwright install chromium
npm run dev    # http://localhost:5173/vimdojo/
npm test       # unit tests (jsdom) and emulation tests (Chromium)
```

## Layout

| Path | What lives there |
|---|---|
| `challenges/` | Level packs (JSON) and their schema. The single source of truth. |
| `plugin/`, `lua/vimdojo/` | The Neovim plugin. `goals`, `scoring`, `progress` and `game` are pure. `app` and `ui` talk to Neovim. |
| `tests/` | plenary specs. `solutions_spec.lua` proves every level is solvable within par. `fixtures/` is shared with the web tests. |
| `web/` | Landing page and browser demo (Vite + TypeScript + CodeMirror). |
| `scripts/par.lua` | Par finder for authors (`make par`). |
| `docs/decisions.md` | Why things are the way they are. Read it before changing a rule. |

## Guidelines

- The plugin has no runtime dependencies. Keep it that way.
- Scoring and goal logic exist in Lua and TypeScript. Change both, and update
  `tests/fixtures/` so the shared tests pin the new behavior.
- Run `make fmt` before committing. CI runs `stylua --check`, `selene`, the
  plugin tests on Neovim stable and nightly, and the web tests.
- Record non-obvious decisions in `docs/decisions.md`.

## Releasing

Push a `vX.Y.Z` tag. `.github/workflows/release.yml` publishes the rock to
luarocks.org (that's what `:Rocks install vimdojo` installs). It needs a
luarocks.org API key in the `LUX_API_KEY` repository secret. On pull requests
the same workflow only builds and installs the rock locally.

## Regenerating the README GIF

```sh
brew install vhs   # or see https://github.com/charmbracelet/vhs
make gif
```
