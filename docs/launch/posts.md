# Channel post drafts

Drafts to post under your own name. Read [channels.md](channels.md) for each
channel's rules first, and [plan.md](plan.md) for the order.

**Rewrite these in your own voice before posting.** Several channels ask for
it outright: Hacker News says "Please don't put generated text in HN posts"
(this covers your first comment), and dev.to and Medium require AI-assisted
posts to say so. Treat the text below as a fact-checked outline. The numbers
are correct for v0.5.0: 84 levels, 16 packs, three tracks, 19 levels in the
browser demo, and a daily challenge picked from those 19.

Links used throughout:

- Repo: https://github.com/navasvarela/vimdojo
- Browser demo and today's daily: https://vimdojo.org
- Discussions: https://github.com/navasvarela/vimdojo/discussions
- GIF: https://raw.githubusercontent.com/navasvarela/vimdojo/main/docs/demo.gif

---

## r/neovim

**Flair:** `Plugin`

**Title** (pick one):

- vimdojo - Vim puzzles scored on keystrokes against par, each level in a clean Neovim
- vimdojo - a Vim puzzle game where par only uses the motions you've learned so far

Titles there are usually "name - one-line description". The "No low-effort
content" rule asks for titles with useful context.

**Body.** Attach the GIF or a short video as the post's media; if you post a
link instead, put the GIF first in the body.

> vimdojo is a game of tiny Vim puzzles. Each level is a few lines of text
> and one goal ("put the cursor on the `q` of `question`", "rename `getUser`
> everywhere"). You're scored on keystrokes and time against a par, golf
> style.
>
> Par is the shortest solution that uses only the motions the game has taught
> so far. The first level's par is `jjjll`; if you already know `Gw`, you beat
> it.
>
> There's a **daily challenge**: one level a day, the same for everyone, at
> the top of the menu (`:VimDojo daily`) and in the browser. `y` on the
> results card copies a spoiler-free line like
> `vimdojo daily 2026-11-03 ★★★ 7 keys (par 7) 4.3s`, so post yours below.
>
> - 84 levels in three tracks: **Motions** (hjkl through text objects,
>   registers, macros, `:g` and `:s`), **Usage** (splits, `gf`, `:find`,
>   `:vimgrep` + `:cdo`, `gc`, `]d`) and **Setup** (write or fix an
>   `init.lua`; behavior probes run your config in a sandboxed headless
>   Neovim and check what it does).
> - Every level runs in its own `nvim --clean` in a terminal window, so your
>   registers, mappings and plugins are never touched, and plugins can't skew
>   par. `config = "mine"` plays with your config instead.
> - Every reference solution is typed into a real Neovim in CI (0.10.4,
>   stable, nightly and Windows) and must finish within par.
> - No dependencies, Neovim 0.10+ (a few levels need 0.11). lazy.nvim:
>   `{ "navasvarela/vimdojo", cmd = "VimDojo", opts = {} }`, or packer,
>   vim-plug, `:Rocks install vimdojo`.
>
> There's also a [browser demo](https://vimdojo.org) with 19 levels and
> today's daily on CodeMirror's Vim emulation, if you want to try it before
> installing.
>
> Levels are plain JSON with a reference solution, so new ones are easy to
> add and CI tells you if the par is wrong. I'd love level ideas, and
> especially reports of pars you beat using only the taught motions: that
> means the par is wrong. Both are welcome in
> [Discussions](https://github.com/navasvarela/vimdojo/discussions).
>
> Repo: https://github.com/navasvarela/vimdojo
>
> [One or two sentences, in your words, on how you built it and the role AI
> played, if any. r/neovim readers ask, and saying it first goes much better
> than being asked.]

Alternative format, recommended by the hardtime.nvim author: keep the post
body to the first two paragraphs and the links, and put the bullet list in
your own first comment.

---

## r/vim

r/vim has a "No Neovim only content" rule, and vimdojo is a Neovim plugin.
Lead with what works for Vim users, the browser demo and the Motions
curriculum, or skip this subreddit. **Flair:** `Plugin` or `Random`.

**Title:** A puzzle game for practising Vim motions, scored on keystrokes
against par (browser demo + Neovim plugin)

**Body:**

> I made a game of small Vim puzzles: a few lines of text, one goal, and a
> par for keystrokes and time. Par only uses motions the game has already
> taught you, so knowing more Vim lets you beat it.
>
> You can try 19 levels in the browser without installing anything, plus a
> daily puzzle that's the same for everyone: https://vimdojo.org
> (CodeMirror's Vim emulation, so key counts can differ slightly from real
> Vim).
>
> The full game (84 levels) is a Neovim plugin: it needs Neovim 0.10+, and
> each level runs in a clean `nvim --clean`. The Motions track (hjkl through
> text objects, registers, macros and Ex commands) applies to Vim as-is.
>
> Feedback on the level design welcome: https://github.com/navasvarela/vimdojo

---

## Show HN

**Title** (80-character limit; no hype, no exclamation marks):

- Show HN: Vimdojo – Vim puzzles scored on keystrokes against par
- Show HN: Vimdojo – Learn Vim motions by golfing tiny puzzles in Neovim

**URL:** the browser demo, https://vimdojo.org (HN asks that people can try
it without signing up; the demo links to the repo).

**First comment.** Post it right after submitting. HN wants the backstory and
what's different, in your words, so use these as notes:

> Hi HN, I made vimdojo because [your reason: e.g. what finally made Vim
> motions stick for you was spotting a shorter way mid-edit and trying it].
>
> It's a game of tiny Vim puzzles scored on keystrokes against a par. Par is
> the shortest solution using only the motions taught so far, so beginners
> can always get three stars and people who know more Vim can beat it.
>
> The browser demo is 19 levels on CodeMirror's Vim emulation, with a daily
> puzzle picked from the date, so everyone gets the same one with no server.
> The real game is a Neovim plugin with 84 levels, and a few things there
> were fun to build:
>
> - Each level runs in a child `nvim --clean` inside a terminal window. The
>   parent counts keys with `vim.on_key`; the child checks the goal itself
>   and notifies the parent over RPC. So your registers, mappings and
>   plugins never touch a level.
> - Every level's reference solution is typed key by key into a real Neovim
>   in CI (0.10.4, stable, nightly, Windows) and must solve the level within
>   par. Cursor-movement pars come from a shortest-path search over real
>   motions; that search pushed several levels out of the curriculum because
>   the "lesson" key wasn't the shortest route.
> - The Setup track has you write or fix an `init.lua`. Your config runs in a
>   headless Neovim with its `XDG_*` dirs in a temp folder, and probes check
>   behavior (press `<Space>w`, write a file and read it back). Infinite
>   loops get SIGKILLed after 3 s, because Neovim handles SIGTERM on its event
>   loop.
>
> It's MIT, no dependencies, no accounts. I'd like feedback on level design,
> and on any par you beat with only the taught motions.
>
> [How you built it, including the role AI played, if any.]

Be ready for these questions (all came up on earlier Vim-trainer threads):
"why not vimtutor?" (vimtutor explains; this is practice with a score), "is
the browser emulation accurate?" (no, it's a taste; the plugin runs real
Neovim, and the demo levels are the ones whose solutions pass in the
emulation), and comparisons with VimGolf and vim-be-good (credit both).

---

## Lobsters

You need an invite. Accounts younger than 70 days can't use the `show` tag
or submit domains the site hasn't seen, so link the GitHub repo (github.com
is known) rather than vimdojo.org, which is new to Lobsters. Tick "I am the
author".

**Title:** vimdojo: Vim puzzles scored on keystrokes, with pars proven in CI

**URL:** https://github.com/navasvarela/vimdojo

**Tags:** `vim`, `show` (if your account allows it), `education` or `games`

If you later publish the article, it's a better Lobsters submission than the
repo (Lobsters prefers write-ups to announcements): "Grading an init.lua by
running it: the sandbox behind vimdojo's Setup levels" or similar, tagged
`vim`, `lua`.

---

## Mastodon / Bluesky thread

Each post is under 300 characters, so the same thread works on both. Attach
the GIF to the first post with the alt text below. Use CamelCase hashtags so
screen readers read them correctly.

**1/4**

> I made vimdojo, a game of tiny Vim puzzles inside Neovim. Each level is a
> few lines of text and one goal, scored on keystrokes against a par. Par only
> uses motions you've been taught so far, so knowing more Vim beats it.
>
> https://github.com/navasvarela/vimdojo #Neovim #Vim

Alt text: "Neovim with the vimdojo menu open. A level asks to put the cursor
on a word; it's solved in five keys and a results card shows three stars,
then the next level starts."

**2/4**

> 84 levels in three tracks: Motions (hjkl to macros and :s), Usage (splits,
> gf, :vimgrep with :cdo) and Setup, where you fix an init.lua and probes run
> it in a sandboxed headless Neovim to check what it does.

**3/4**

> Every level runs in its own nvim --clean, so your config and plugins never
> touch it. CI types every reference solution into real Neovim (0.10, stable,
> nightly, Windows) and checks it fits par.

**4/4**

> No install needed: 19 levels and today's daily puzzle in the browser.
> Everyone gets the same daily, and you can copy a spoiler-free score to
> reply with. https://vimdojo.org #OpenSource #NeovimPlugin

---

## awesome-neovim PR

Eligible from **2026-10-24** (the list wants plugins at least a week old;
the repo was created 2026-10-17).

**PR title:** ``Add `navasvarela/vimdojo` ``

**Section:** `## Game`, appended at the end of the list.

**Line:**

```markdown
- [navasvarela/vimdojo](https://github.com/navasvarela/vimdojo) - Learn Vim motions, workflows and Lua configuration through tiny puzzles scored on keystrokes against par.
```

Shorter alternative:

```markdown
- [navasvarela/vimdojo](https://github.com/navasvarela/vimdojo) - Learn Vim through tiny puzzles scored on keystrokes against par.
```

**PR body:** keep the template exactly; fill in the repo URL and tick the
boxes:

```markdown
### Repo URL:

https://github.com/navasvarela/vimdojo

### Checklist:

- [x] The plugin is specifically built for Neovim.
- [x] The plugin is licensed.
- [x] The lines end with a `.`. This is to conform to `awesome-list` linting and requirements.
- [x] The title of the pull request is ```Add/Update/Remove `username/repo` ``` (notice the backticks around ``` `username/repo` ```) when adding a new plugin.
- [x] The description doesn't mention that it's a Neovim plugin, it's obvious from the rest of the document. No mentions of the word `plugin` unless it's related to something else. No `.. for Neovim`.
- [x] The description doesn't contain emojis.
- [x] Neovim is spelled as `Neovim` (not `nvim`, `NeoVim` or `neovim`), Vim is spelled as `Vim` (capitalized), Lua is spelled as `Lua` (capitalized), Tree-sitter is spelled as `Tree-sitter`.
- [x] Acronyms (`LSP`, `TS`, `YAML`, etc.) are fully capitalized.
```

Run `./scripts/readme-check.sh` in your fork before opening it.

---

## neovim/neovim GitHub Discussions, "Show and tell"

**Title:** vimdojo: Vim puzzles scored on keystrokes, each level in a clean
`nvim --clean`

**Body:** reuse the r/neovim body. Add a sentence on what might interest
Neovim developers specifically: the parent/child RPC design
(`nvim_set_client_info` to find the child's channel, goal checks pushed with
notifications), and that the Setup sandbox found a real-world gotcha
(`vim.system`'s timeout sends SIGTERM, which a busy-looping config never
handles). The daily challenge is picked from the date with a seeded
shuffle (MINSTD, exact in both Lua and JavaScript), so the plugin and the
site agree with no server.
