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

The full contract is [`challenges/schema.json`](../challenges/schema.json).
Point your editor's JSON support at it via `"$schema": "./schema.json"`.

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
motions and prints the taught-motion optimum (which should equal
`par_keys`) next to the any-motion optimum:

```
basic-motions-01   par  5 | taught  5 jjjll      | any  2 Gw
```

For `buffer_equals` levels, work the par out by hand. Keep `solution` at or
under `par_keys`.

`par_seconds` is a generous time for someone who knows the answer: usually
1-2 seconds per key, and never less than 5 seconds.

## Checking your level

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

It prints `ok`/`FAIL` for every level. Any level marked `web_demo` must pass.

## Adding a pack

Create `challenges/NN-name.json` with `pack`, `title`, `description`, a
unique `order` and its `levels`. Packs unlock in `order`. No code changes are
needed: the plugin, the demo and the landing page pick it up automatically.

## Adding a goal type

A new goal type touches three places that must stay in sync:
`challenges/schema.json`, `lua/vimdojo/goals.lua` (plus the presentation
in `lua/vimdojo/ui.lua`) and `web/src/goals.ts` (plus
`web/src/game/goal-view.ts`). Add cases to `tests/fixtures/goals.json` so both
implementations are tested against the same expectations.
