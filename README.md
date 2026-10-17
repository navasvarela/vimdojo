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

## Playing

| Key / command | Action |
|---|---|
| `:VimDojo` | Open the level menu (`<CR>` to play, `q` to close) |
| `<leader>h` / `:VimDojo hint` | Show the hint (caps the attempt at 2 stars) |
| `<leader>r` / `:VimDojo reset` | Restart the level |
| `<Esc><Esc>` / `:VimDojo quit` | Leave the level |

The timer starts on your first key. Every physical key counts (`d2w` is 3
keys, `<Esc>` is 1). The game's own control keys are never counted. A level is
solved as soon as the goal holds in Normal mode.

## Configuration

```lua
require("vimdojo").setup({
  unlock_all = false, -- skip progression locks
  window = "float",   -- "float" | "tab"
  progress_path = nil, -- defaults to stdpath("data")/vimdojo/progress.json
  keymaps = { hint = "<leader>h", reset = "<leader>r", quit = "<Esc><Esc>" },
})
```

Levels are judged against stock Vim behavior. If your config remaps a motion,
it applies in the game buffer too.

## Development

```sh
make deps      # clone plenary.nvim into .deps/ (dev only)
make test      # plugin unit tests + every level's reference solution
make lint      # stylua --check and selene
make validate  # validate challenges/*.json against challenges/schema.json
```

The web demo lives in `web/` (Vite + TypeScript + CodeMirror 6 with
`@replit/codemirror-vim`):

```sh
cd web
npm install
npx playwright install chromium  # once, for the emulation tests
npm run dev    # http://localhost:5173/vimdojo/
npm test       # unit tests (jsdom) + emulation tests (Chromium)
npm run build
```

Design decisions are logged in [docs/decisions.md](docs/decisions.md).

## License

MIT
