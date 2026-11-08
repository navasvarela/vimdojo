# Changelog

## v0.13.0 (2026-11-08)

### Added

- **Link previews for shared results.** The link in a copied result, from the plugin or
  the site, now goes to a page for that level, `https://vimdojo.org/play/<level>/?beat=<keys>`,
  so Slack, Discord, X and other apps show a card with the level's name, pack, par and
  what it asks for. The page forwards to the level in the browser with the count to beat.
  Links copied before this still work. The landing page and the boards have cards too.
- **Practice on the site.** `Alt+P` while playing a level, or Practice (P) on the results
  card, plays it again with nothing recorded and free hints, as `p` does in the plugin.
  The practice card shows your keys beside par; Play for real (P) switches back.
- **A menu at the top of every page of the site:** Play, Daily, Leaderboards, Install and
  Account. `vimdojo.org/#daily` opens today's daily straight away, and the boards link to it.
- **A way in for first-time visitors.** Before a level is picked, the site offers to start
  the first unsolved level, or today's daily.
- **The site says what else there is.** Each pack in the level list says how many more
  levels the plugin has, and the packs the browser can't play are listed at the end.
- `robots.txt`, a sitemap, canonical links and a vimdojo 404 page.

### Changed

- The plugin's message for a locked level mentions `unlock_all`.
- The site's results card lists the keys you typed, as the plugin's does, and its
  buttons wrap whole on narrow screens instead of breaking their labels over lines.
- **Fixed:** opening a level or lesson from low in the site's level list left it out of
  view, above the screen or, on a phone, below the list. It now scrolls into view.
- The landing page's button says "Play in your browser" rather than "Play the demo".

## v0.12.0 (2026-11-07)

### Added

- **Pack lessons.** Every pack except Boss Levels now opens with a short lesson: the idea
  behind its levels, each command they teach with a worked example, and the `:help` tags
  to read next. It shows before a level you pick from the menu until you've solved one
  of the pack's levels, and `L` on the menu (the Lesson link on the site) shows it any
  time. The daily, practice and "beat my keys" links go straight to the level. Packs can
  carry a `lesson`, and validation checks it covers every command the levels teach.

## v0.11.0 (2026-11-04)

### Added

- **The overall board.** [vimdojo.org/boards](https://vimdojo.org/boards/) ranks players
  across every ranked level: the most levels verified, then the fewest keys over par in
  total. Profiles show each player's place, levels and keys over par.
- **Step-by-step par routes for Regex Power and Boss Levels.** After you solve one of these
  levels, the results card breaks the par route into steps and says what each one does.
  It's hidden on today's daily, like the route. Levels can carry an `explain` list, and
  validation checks its steps add up to the solution exactly.
- **"Beat my keys" links.** The result you copy with `y` (or Copy result on the site) now
  ends with a link to that level and your count, such as
  `https://vimdojo.org/?play=macros-01&beat=7`. It opens the level in the browser demo
  with your count to beat, and says whether the new player beat it. Still spoiler-free:
  it never includes your keys. For a level that's only in the plugin, the site says so.
- **Watch par on the site.** `W` on the results card plays the level's par route on its
  own text, one key at a time, with the keys typed so far shown underneath. It's hidden
  on today's daily, like the route itself.

## v0.10.0 (2026-11-04)

### Added

- **Tips.** When you solve a level over par, the results card suggests one shorter way to
  type what you typed, from your own keys: a count instead of `jjjj`, `cw` instead of `dwi`,
  `A` instead of `$a`. In Neovim and on the site, offline.
- **Web runs.** Sign in on the site, solve a level in the browser demo, and submit it from
  the results card (`S`). The server replays your keys in real Neovim, so web and plugin
  players share one board, and today's daily ranks the same way. A run with pasted text,
  or with a key the demo can't record, can't be submitted.

## v0.9.0 (2026-11-03)

### Added

- **Daily streaks.** Solving the daily on consecutive UTC days builds a streak, shown on
  the menu and the results card, in Neovim and on the site. It's kept with your progress,
  so it needs no account.
- **Practice mode.** `p` on a level in the menu, or `:VimDojo practice {level}`, plays it
  with nothing recorded: no progress, stars, streak, key log or submission, and hints
  cost nothing.

## v0.8.0 (2026-11-02)

### Added

- **Three more packs in the Motions track, 26 levels, all ranked.**
  - **Marks and Jumps:** `m`, backtick and `'` as motions, capital marks across files,
    `<C-o>` and `g;`.
  - **Ex Ranges:** `:t`, ranges inside `:g`, relative addresses, marks as addresses,
    `:argdo` and building the argument list.
  - **Filters and Formatting:** `!` with `sort`, `gq`, `gw` and `=`.

### Changed

- Usage and Setup packs moved from orders 13-19 to 16-22, so the new packs follow Boss
  Levels. Progress and leaderboards aren't affected.

## v0.7.2 (2026-11-01)

### Fixed

- With three or more panels open, such as help and a board over the menu, closing them
  could leave a panel showing with the keys going somewhere behind it, so it couldn't be
  closed. Closing a panel now returns to the one underneath.

## v0.7.1 (2026-11-01)

### Fixed

- `:VimDojo daily` with the menu or help open started the level underneath them, where
  it couldn't be seen, and every key went to the hidden level. Starting a level now
  closes any open panel, and opening the menu twice no longer stacks a second one.

## v0.7.0 (2026-11-01)

### Added

- **Three advanced packs in the Motions track, 25 levels, all ranked.** The hardest
  par was 42 keys, and few levels combined skills.
  - **Regex Power:** `\v`, groups and backreferences, `&`, `\u`, `\zs`, `\ze`,
    `\{-}` and lookaround (`\@!`, `\@<!`).
  - **The Expression Register:** `<C-r>=`, `:put =` and `\=` in substitutions.
  - **Boss Levels:** seven realistic refactors with pars from 49 to 62 keys, such as
    extracting a function or turning a git log into release notes.
- **Help inside the game.** `?` on the menu or the results card, or `:VimDojo help`,
  opens a panel with how to play, scoring, the keys you've configured, the commands and
  how to turn on the leaderboards. `:help vimdojo` is still the full manual.
- **See how par is done.** The results card now shows your keys beside the level's
  par route and what the level teaches, in Neovim and on the site. On today's daily
  the route stays hidden until the day ends, so the board can't be climbed by copying.
- **Daily boards.** The daily challenge now has a board for each UTC day, starting
  empty: `:VimDojo board daily`, `b` on a daily's results card, or the top of
  [the boards page](https://vimdojo.org/boards/), which links back through past days.
  A verdict on today's level says your place today. The server's clock decides what
  counts, so nothing can be backfilled.

### Fixed

- Sending a run the server had already verified raised an error in the plugin instead
  of reporting the verdict.

## v0.6.0 (2026-10-31)

### Added

- **Leaderboards, right in Neovim.** Optional and off by default: set
  `online = { enabled = true }`, then `:VimDojo login`. `s` on the results card
  submits a run, a server replays it in a clean Neovim and recounts the keys, and the
  verdict and your place show up in a few seconds. `b` on the results card or
  `:VimDojo board [level]` shows a level's board, and `:VimDojo scores` shows your
  bests, places and anything you haven't sent. `:VimDojo submit` sends everything
  you've played.
- Boards rank by verified keys, then by who got there first, and show handles and
  counts only. Your keys are the level's solution, so they stay private. Setup levels
  aren't ranked.
- **On the site:** [leaderboards](https://vimdojo.org/boards/), public profiles, an
  [account page](https://vimdojo.org/account/) to manage logins, export or delete your
  data, and a [privacy page](https://vimdojo.org/privacy/).
- The plugin keeps your best run per level in `stdpath("state")/vimdojo/keylogs`, which
  stays on your machine unless you submit it.
- A [security policy](https://github.com/navasvarela/vimdojo/blob/main/SECURITY.md).

### Changed

- Without a connection, a submitted run waits, and is sent the next time you use an
  online command.
- The site's footer now says it sets no cookies unless you sign in.

## v0.5.0 (2026-10-30)

### Added

- **Daily challenge:** one level a day, the same for everyone, in the plugin
  and on https://vimdojo.org. It sits at the top of the menu, or run
  `:VimDojo daily`. It's picked from the date (UTC) with no network access,
  plays every demo level once before any repeats, and ignores pack locks.
- **Share your result:** `y` on the results card (Copy result on the site)
  copies a spoiler-free line such as
  `vimdojo daily 2026-10-30 ★★★ 7 keys (par 7) 4.3s` with the site link. It
  gives your score, never your keys.
- **Community:** GitHub Discussions for level ideas, dailies and beaten pars,
  linked from the README and the site.
- **For authors:** an optional `authors` field (GitHub handles) on packs and
  levels, credited on the site; a pull request template with the level review
  checklist; and a licensing note in CONTRIBUTING.
- The site lists the curriculum by track, with a "Neovim only" badge on Usage
  and Setup, and now lives at https://vimdojo.org.

### Fixed

- Pasted text now costs what typing it would (one key per character), in the
  plugin and the browser demo. Before, pasting a solution cost no keys.

## v0.4.0 (2026-10-19)

### Added

- **Setup track:** 18 levels in four packs (Options and Keymaps,
  Autocommands and Commands, Fix the Broken Config, Modern Neovim). You edit
  an `init.lua`; the game runs it in a sandboxed Neovim and shows inline,
  as you type, which checks still fail. Modern Neovim needs 0.11. All three
  tracks are complete: 84 levels.
- CI runs the plugin tests on Neovim 0.10.4, the oldest supported release,
  as well as stable, nightly and Windows.

### Fixed

- Packs no longer fail to load on Neovim 0.10 because a 0.11-only level
  names a 0.11 option.
- The yank-highlight check works on Neovim 0.10.

## v0.3.0 (2026-10-19)

### Added

- **Usage track:** 13 levels in three packs (Windows and Buffers,
  Project-Wide Edits, Neovim Built-ins), played in a real workspace of files:
  splits, the alternate file, `gf`, `:find`, `:vimgrep` with `:cdo`, `gc`,
  `g&`, `]q` and `]d`. 66 levels in total. The quickfix level needs
  Neovim 0.11.
- **Setup-track engine:** levels where you edit an `init.lua` that behavior
  probes check in a sandboxed Neovim. The Setup curriculum comes in a later
  release.
- **For authors:** workspace `files` with `open`, `preset.commands`, and the
  `files_equal`, `layout` and `config_probes` goals. Failing solution tests
  print the level's `:messages`.

### Fixed

- `<C-^>` and other modifier + punctuation keys count as one key.
- Windows: quitting Neovim mid-level no longer leaves the level's Neovim
  running.

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
