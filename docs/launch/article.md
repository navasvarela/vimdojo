# Article draft

For dev.to, Hashnode or a personal blog. About 1,300 words of prose. Post
it on your own blog first if you have one, then cross-post with a
`canonical_url` pointing at it (see [channels.md](channels.md)).

Suggested tags: dev.to `#vim #neovim #showdev #opensource` (dev.to allows four).
Hashnode: `vim`, `neovim`, `open-source`, `lua`.

Cover image: `docs/brand/social-preview.png` (1280×640), or the first frame
of `docs/demo.gif`. Put the GIF in the body right after the first section.

Before publishing, check the numbers against the release you're linking
(they are correct for v0.5.0: 84 levels, 16 packs, 19 in the browser demo,
and a daily challenge picked from those 19).

This draft is AI-assisted. Rewrite it in your own voice. dev.to and Medium
require AI assistance to be disclosed if any of it remains, and readers on
r/neovim care how projects are built (see
[channels.md](channels.md#the-issue-that-cuts-across-channels-ai)). A short
paragraph on how you built vimdojo, including the role AI played, would fit
naturally after "A clean Neovim for every level".

---

## Title options

1. I built a Vim puzzle game where every keystroke counts
2. Learning Vim by golfing tiny puzzles, inside Neovim
3. vimdojo: Vim puzzles scored on keystrokes, with pars proven in CI

---

# I built a Vim puzzle game where every keystroke counts

Most people learn Vim the same way: `vimtutor` once, a cheat sheet taped to
the monitor, and then months of `jjjjjjj` until something sticks. I did that
too. What finally made motions stick for me wasn't reading about them. It was
noticing, mid-edit, that there was a shorter way, and trying it.

So I built a game around that moment. It's called **vimdojo**: a Neovim
plugin of small puzzles where you're scored on keystrokes against a par,
like golf.

![vimdojo: open the menu, solve a level in five keys, and move on](https://raw.githubusercontent.com/navasvarela/vimdojo/main/docs/demo.gif)

## How a level works

Each level is a few lines of text and one goal. "Put the cursor on the `q`
of `question`." "Remove the stray word `fxo`." "Rename `getUser` to
`fetchUser` in every file." You solve it with Vim keys. A timer starts on
your first key, a counter tracks every physical key you press (`d2w` is three
keys, `<Esc>` is one), and the level ends the moment the goal holds in Normal
mode.

You get up to three stars: three for matching par on both keys and time, two
for staying within 1.5 times par, one for solving it at all. There's a hint if
you're stuck, but it caps you at two stars.

The rule that makes it a game is how par is set. **Par is the shortest
solution that uses only the motions the game has taught so far.** The very
first level teaches `j` and `l`, and its par is `jjjll`: five keys. If you
already know Vim, `Gw` does it in two. Beginners can always reach three stars
with what they've been shown, and anyone who knows more can beat par. That
second part is where most of the fun is.

There are 84 levels in 16 packs, across three tracks:

- **Motions:** from `hjkl` and `w` through `f`/`t`, operators, visual block
  mode, search, text objects, `<C-a>`, registers, macros and Ex commands.
- **Usage:** working in Neovim rather than in a single buffer: splits, the
  alternate file, `gf`, `:find`, `:vimgrep` with `:cdo`, and built-ins like
  `gc` and `]d`.
- **Setup:** you edit an `init.lua` to set options, keymaps, autocommands
  and user commands, or fix a broken one. The game checks what the config
  *does*, not what it looks like.

## A clean Neovim for every level

The first version ran levels in the player's own Neovim. That's fine for
`hjkl`, but advanced levels run into the player's setup. An autopairs plugin
changes what `ci"` leaves behind. A remapped `n` ruins a search level. A
completion menu eats `<C-n>`. And a level that plays with registers or window
layouts would mess up your actual session.

So every level now runs in its own child `nvim --clean`, inside a terminal
window that the game owns. The parent Neovim draws the header, timer and
results card, and counts your keys with `vim.on_key`. The child connects
back over RPC and runs the goal check itself on `TextChanged`,
`CursorMoved` and mode changes, then tells the parent when you're done.
Nothing polls.

That gives isolation for free: your registers, marks, options, mappings,
plugins and windows are never touched, and every player gets the same stock
defaults. If you'd rather practice with your own setup, `config = "mine"`
starts the child with your config instead.

## Pars that are proven, not guessed

A golf game is only as good as its pars. If par is wrong, the game teaches
the wrong lesson, or it makes three stars impossible.

Every level ships with a reference solution, and the test suite types it,
key by key, into a real clean-room Neovim through the same path a player
uses. It has to reach the goal, and it has to be counted as exactly its own
length, within par. CI runs that on Neovim 0.10.4, stable and nightly, plus
Windows, where named pipes and ConPTY behave differently. (A few levels need
0.11 and are skipped on 0.10.)

For cursor-movement levels, a par finder (`make par`) runs a shortest-path
search over cursor positions in headless Neovim, using real motions. It
reports two numbers: the best with the motions taught so far, which must equal
par, and the best with any motion. Editing levels are worked out by hand.

Keeping pars honest changed the curriculum. A level only teaches well if its
new key is actually the shortest route. Plain `v` plus an operator usually
loses to an operator with a motion, so the Visual Mode pack teaches block
mode instead. Several register levels were dropped because a plain yank and paste
beat `"0p`. And the tests caught a mistake in the very first example level I
wrote down: its solution, `fxdw`, leaves part of the word behind, because
`dw` starts on the `x`.

## The Setup track: grading a config by running it

The Setup levels were the most interesting to build. You're given a small
`init.lua` and a goal like "use `<Space>` as the leader so `<Space>w` saves"
or "this config fails to load; make `shiftwidth` 2". As you edit it, the game
runs your config in a separate headless Neovim with every `XDG_*` directory
pointed into a temporary folder, then runs behavior probes against it: read
an option from a new buffer, press keys and look at the result, write a file
and check what landed on disk.

A few things I learned on the way:

- `vim.system`'s timeout sends SIGTERM, which Neovim handles on its event
  loop. A config stuck in `while true do end` never gets back to the loop, so
  the sandbox kills it with SIGKILL after three seconds.
- Load errors are reported on the line that caused them, even when the error
  is raised deep inside the runtime (a `nil` passed to `vim.keymap.set`).
- Probes have to test the real outcome. My first "trim whitespace on save"
  probe checked the buffer after `:w`, and a wrong config passed. It now
  re-reads the file from disk.

This is isolation, not a security sandbox: it's your own code on your own
machine. The point is that it never touches your real config or data.

## A puzzle a day

Every day there's one daily level, the same for everyone. It's at the top of
the plugin's menu (`:VimDojo daily`) and on the site. There's no server
behind it: both clients pick the level from the date, using the same seeded
shuffle, written once in Lua and once in TypeScript and pinned by a shared
test fixture. Each cycle plays every demo level once, and the same level
never comes up two days running.

When you solve it, `y` on the results card copies a line like
`vimdojo daily 2026-11-03 ★★★ 7 keys (par 7) 4.3s`. It gives your score but
not your keys, so you can post it without spoiling the solution for anyone
else.

## Try it

There's a [browser demo](https://vimdojo.org) with 19 levels and the daily, using
CodeMirror's Vim emulation. Every demo level's solution is checked against
the emulation in real Chromium, but browser key counts can differ from
Neovim's in edge cases, so treat web scores as indicative.

For the real thing, install the plugin (Neovim 0.10+, no dependencies). With
lazy.nvim:

```lua
{ "navasvarela/vimdojo", cmd = "VimDojo", opts = {} }
```

It also works with packer, vim-plug, and `:Rocks install vimdojo`. Then run
`:VimDojo`. Your progress is saved between sessions.

## Contribute a level

Levels are plain JSON: start text, a goal, a par, and a reference solution.
CI proves every new level solvable within par in real Neovim, so you find out
straight away if your par is too tight or your solution doesn't work. If you
have a favorite trick (a text object people don't know, a `:g` one-liner, an
`init.lua` mistake you made once), it would probably make a good level. The
authoring guide is in
[docs/authoring-levels.md](https://github.com/navasvarela/vimdojo/blob/main/docs/authoring-levels.md).

Bug reports are welcome too, especially pars you managed to beat with only
the taught motions. That means the par is wrong, and I'd like to know. Ideas,
beaten pars and daily scores go in
[Discussions](https://github.com/navasvarela/vimdojo/discussions).

The code is MIT-licensed on
[GitHub](https://github.com/navasvarela/vimdojo). The design decisions,
including the ones that didn't work out, are written up in
[docs/decisions.md](https://github.com/navasvarela/vimdojo/blob/main/docs/decisions.md).
