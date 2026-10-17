# vimdojo

Learn Vim motions by solving tiny puzzles, right inside Neovim.

Each level gives you a snippet of text and a goal ("delete the typo", "put the
cursor on the last word"). Solve it with Vim keystrokes and you are scored on
keystrokes, time, and a per-level par.

> Status: early development. See [PLAN.md](PLAN.md) for the roadmap.

## Install

Requires Neovim 0.10+. No runtime dependencies.

```lua
-- lazy.nvim
{ "navasvarela/vimdojo", cmd = "VimDojo", opts = {} }
```

Then run `:VimDojo`.

## Development

```sh
make deps      # clone plenary.nvim into .deps/ (dev only)
make test      # plugin unit tests + every level's reference solution
make lint      # stylua --check and selene
make validate  # validate challenges/*.json against challenges/schema.json
```

Design decisions are logged in [docs/decisions.md](docs/decisions.md).

## License

MIT
