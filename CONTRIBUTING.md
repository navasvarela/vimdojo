# Contributing

Thanks for helping! New levels are the most valuable contribution. Start with
[docs/authoring-levels.md](docs/authoring-levels.md).

## Licensing

vimdojo is MIT-licensed, and contributions are accepted under the same
license: by opening a pull request, you license your contribution under the
project's [MIT license](LICENSE). Level text must be your own or
MIT-compatible, so no song lyrics, book excerpts or code copied from GPL
projects.

## Talking about vimdojo

[Discussions](https://github.com/navasvarela/vimdojo/discussions) is the
place for level ideas, the daily challenge, beaten pars and questions. Bugs
go in issues. Post solutions inside a spoiler block
(`<details><summary>Solution</summary> … </details>`), and daily solutions
only after the day has ended (UTC).

## Setup

You need Neovim 0.10+, `make`, `git`, [stylua](https://github.com/JohnnyMorganz/StyLua),
[selene](https://github.com/Kampfkarren/selene) and Node.js 22 for the web demo.

```sh
make deps   # clones plenary.nvim into .deps/ (dev only)
make all    # lint, schema validation, help-file check, plugin tests
make check  # everything CI runs: the above, plus the web checks and actionlint
make fmt    # format Lua (stylua) and the web code and level JSON (Biome)
```

Web demo:

```sh
cd web
npm install
npx playwright install chromium
npm run dev    # http://localhost:5173/
npm test       # unit tests (jsdom) and emulation tests (Chromium)
npm run lint   # Biome lint and format check (web code, level packs, fixtures)
npm run fix    # apply Biome's formatting and safe fixes
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
- Run `make fmt` before committing, and `make check` before pushing. CI runs
  the same checks: stylua and selene for Lua, Biome for TypeScript, CSS and
  JSON (including level packs), schema validation, the plugin tests on Neovim
  0.10.4, stable, nightly and Windows, the web tests and build, and actionlint
  for the workflows.
- Record non-obvious decisions in `docs/decisions.md`.
- CI runs every pull request's own levels, so treat workflow changes with
  care: keep `pull_request` (never `pull_request_target`), read-only
  `permissions`, and third-party actions pinned to a commit SHA.

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
