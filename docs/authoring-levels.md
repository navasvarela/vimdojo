# Writing levels

Levels are plain JSON in `challenges/`, one file per pack. The same files feed
the Neovim plugin, the web demo and the landing page's curriculum, so a level
is written exactly once.

## A level

```json
{
  "id": "operate-01",
  "title": "Kill the typo",
  "description": "Remove the stray word 'fxo' so the sentence reads correctly.",
  "start_text": ["The quick brown fxo jumps over the lazy dog"],
  "cursor_start": [1, 0],
  "goal": { "type": "buffer_equals", "value": ["The quick brown jumps over the lazy dog"] },
  "par_keys": 4,
  "par_seconds": 8,
  "hint": "Jump to the typo with f, then delete the word with dw.",
  "solution": "ffdw",
  "teaches": ["dw"],
  "web_demo": true
}
```

| Field | Meaning |
|---|---|
| `id` | Globally unique, kebab-case. Progress is keyed by it, so never rename a published id. |
| `start_text` | The buffer as an array of lines (no trailing newlines). |
| `cursor_start` | `[line, col]`: **1-based line, 0-based byte column**, like `nvim_win_get_cursor()`. |
| `goal` | `buffer_equals` (exact text) or `cursor_at` (`line`, `col`; the text must be unchanged unless `"allow_edit": true`). |
| `par_keys` / `par_seconds` | The bar for 3 stars. See the par rule below. |
| `hint` | Shown on request. It caps the attempt at 2 stars. |
| `solution` | A reference solution in key notation (`ciwfoo<Esc>`). Tests run it. Players never see it. |
| `teaches` | The keys this level introduces. Used for the par rule and the curriculum listing. |
| `web_demo` | Include the level in the browser demo. Only set it when the emulation test passes. |
| `requires` | Optional. `{ "nvim": "0.11" }` for levels that need newer defaults or APIs. Older Neovims show the level as unavailable and skip it. |
| `options` | Optional. Options set like `:set` before the level starts, e.g. `{ "shiftwidth": 2, "wrapscan": false }`. |
| `preset` | Optional. `registers` (`{ "a": "charwise text" }` or `{ "a": ["linewise", "lines"] }`) and buffer `marks` (`{ "m": [line, col] }`) set before the timer starts. |

### Levels with files (Usage track)

Instead of `start_text`, a level can ship a small project:

```json
"files": { "main.lua": ["..."], "src/util.lua": ["..."] },
"open": "main.lua",
"preset": { "commands": ["vsplit src/util.lua"] }
```

The files are written to a fresh directory that becomes the working
directory, and `open` is edited. `cursor_start` applies to it. `preset.commands`
are Ex commands run before the timer starts, to set up splits, quickfix lists
(`silent vimgrep /x/j **`, `cfirst`) or diagnostics
(`lua vim.diagnostic.set(...)`). Levels with files or commands can't be
`web_demo`.

### Goal types

| Type | Shape | Met when |
|---|---|---|
| `buffer_equals` | `{ "value": [lines] }` | The text matches exactly. |
| `cursor_at` | `{ "line", "col", "allow_edit"? }` | The cursor is there and the text is unchanged (unless `allow_edit`). |
| `register_contains` | `{ "register", "value": [lines], "linewise"? }` | The register holds these lines (and has that type, if `linewise` is given). Registers a goal reads start empty. |
| `all_of` | `{ "goals": [goal, ...] }` | Every inner goal holds at once. |
| `files_equal` | `{ "files": { "path": [lines] } }` | Each workspace file holds these lines (unsaved buffer edits count). |
| `layout` | `{ "layout": ["row", [["leaf", "a.lua"], ["leaf", "b.lua"]]] }` | The current tab's windows match, like `winlayout()` with file names. |
| `config_probes` | `{ "probes": [probe, ...] }` | Setup levels: the buffer, loaded as an `init.lua` in a sandboxed Neovim, loads without errors and passes every probe. See below. |

Goals are only checked in Normal mode, so an edit is done when the player
leaves Insert mode.

### Tracks

A pack belongs to one `track`: `motions` (default), `usage` or `setup`.
Tracks unlock independently, and packs unlock in `order` within their track.
Pack `order` is unique across all packs.

The full contract is [`challenges/schema.json`](../challenges/schema.json).
Point your editor's JSON support at it via `"$schema": "./schema.json"`.

### Setup levels and probes

A Setup level's `start_text` is an `init.lua` starter snippet (the room
gives it filetype `lua`), and its goal is `config_probes`. Whenever the
buffer settles in Normal mode (400 ms after the last change), the room
writes it to a temporary `init.lua` and runs it in
`nvim --headless --clean` with temporary `XDG_*` directories and a 3 s
timeout. Load errors and failed probes show as diagnostics in the buffer and
cost the player no keys. Probes check what the config **does**, not how it's
written, so `vim.keymap.set(...)` and `vim.cmd("nnoremap ...")` both pass.

```json
"goal": {
  "type": "config_probes",
  "probes": [
    { "kind": "option", "name": "relativenumber", "value": true },
    {
      "kind": "keys",
      "description": "<leader>w saves a changed file",
      "keys": "ccchanged<Esc><leader>w",
      "lines": ["original"],
      "expect": { "lines": ["changed"], "modified": false }
    }
  ]
}
```

Every probe takes an optional `description` for the level header; each kind
has a default. Probes run in order, each starting from one window on an
empty buffer.

| Kind | Shape | Passes when |
|---|---|---|
| `option` | `{ "name", "value" }` | The option has this value in a new buffer. |
| `keys` | `{ "keys", "lines"?, "cursor"?, "expect" }` | After typing `keys` in a fixture file holding `lines`, every `expect` field matches: `lines`, `cursor`, `modified`, `hlsearch` (`v:hlsearch`), `windows` (in the tab). |
| `filetype` | `{ "filetype", "expect": { option: value } }` | A new buffer of that filetype gets these options (e.g. from a `FileType` autocommand). |
| `command` | `{ "command", "lines", "expect": [lines] }` | Running the Ex command (no colon) on `lines` leaves `expect`. |
| `source_twice` | `{ "event" }` | Sourcing the config again doesn't add autocommands for the event (an augroup with `clear = true`). |
| `extmarks_after` | `{ "keys", "lines"?, "cursor"?, "namespace"?, "min"? }` | Typing `keys` leaves at least `min` (1) extmarks, e.g. `vim.hl.on_yank()`. Leave out `namespace` to count all, which survives renames between Neovim versions. |
| `lua` | `{ "expr", "description" }` | The Lua expression is `true`. An escape hatch, reviewed in PRs: prefer a declarative kind, and add a kind when the same expression shows up twice. |

In `keys`, `<leader>` means the leader the config set, so a probe keeps
working whatever leader the player picks. The fixture is a real file, so
`:w` and `BufWritePre` work.

- **The par is a keystroke edit of the starter snippet** (decision D2), like
  any other level. The reference `solution` must reach a config that passes
  every probe; `solutions_spec.lua` proves it in a real room.
- **Mind the defaults.** Neovim's own ftplugins set options too (Python's
  sets `shiftwidth=4`), so pick a filetype whose defaults don't already pass.
- **Setup levels never get `web_demo`**: the browser can't run a config.
  Loading a pack rejects the combination.

## Rules of thumb

- **One idea per level.** The level should be about its `teaches` keys.
- **Use real-looking text.** Code, config or prose with a bit of humor beats
  "foo bar".
- **Make the goal unambiguous.** If two reasonable end states exist and
  `buffer_equals` would reject one, change the level rather than the checker.
- **The start must not already satisfy the goal.** The tests enforce this.
- **Don't rely on options players may change** beyond Neovim's defaults
  (e.g. `gg` keeps the column because of the default `nostartofline`, so a
  level that depends on it should still work if `gg` lands on the first
  non-blank).

## The par rule

`par_keys` is the **shortest solution using only the motions taught so far**:
every earlier level's `teaches`, plus this level's, plus `h j k l`. Beginners
can always get 3 stars with what the game has shown them. Players who know
more motions can beat par, which is half the fun.

For `cursor_at` levels, `make par` searches every level with real Neovim
motions (including `/`, `?`, `*` and `#` searches) and prints the taught-motion optimum (which should equal
`par_keys`) next to the any-motion optimum:

```
basic-motions-01   par  5 | taught  5 jjjll      | any  2 Gw
```

For `buffer_equals` levels, work the par out by hand. Keep `solution` at or
under `par_keys`.

`par_seconds` is a generous time for someone who knows the answer: usually
1-2 seconds per key, and never less than 5 seconds.

## Checking your level

Play your pack in Neovim before sending it:

```lua
require("vimdojo").setup({ challenges_dir = "/path/to/your/packs", unlock_all = true })
```

Then run the checks:

```sh
make validate   # JSON Schema
make test       # includes tests/solutions_spec.lua
make par        # for cursor_at levels
```

`solutions_spec.lua` opens every level in headless Neovim, checks the goal
is not met at the start, types the `solution` and checks that the goal is met
within `par_keys`.

To flag a level for the web demo, run the emulation test in real Chromium:

```sh
cd web && npx vitest run --project browser --silent=false
```

It presses the solution's keys in real Chromium and prints `ok`/`FAIL` for every
level. Any level marked `web_demo` must pass. Some features aren't emulated
(see the M9 notes in `docs/decisions.md`), so check before flagging.

## Adding a pack

Create `challenges/NN-name.json` with `pack`, `title`, `description`, a
unique `order` and its `levels`. Packs unlock in `order`. No code changes are
needed: the plugin, the demo and the landing page pick it up automatically.

## Adding a goal type

A new goal type touches three places that must stay in sync:
`challenges/schema.json`, `lua/vimdojo/goals.lua` (plus the presentation
in `lua/vimdojo/goal_views.lua`) and `web/src/goals.ts` (plus
`web/src/game/goal-view.ts`). Add cases to `tests/fixtures/goals.json` so both
implementations are tested against the same expectations.
