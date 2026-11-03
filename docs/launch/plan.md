# Launch plan

The goal is for Neovim and Vim users to hear about vimdojo once, from a post
that's easy to try, and for the first wave of feedback to turn into fixes and
new levels. Channel rules and sources are in [channels.md](channels.md); the
drafts are in [posts.md](posts.md) and [article.md](article.md).

r/neovim's Rule 10 bans day-one plugin announcements: a plugin needs two months of
continuous development first. vimdojo's first commit was on 2026-10-17, so the
earliest r/neovim post is **Thursday 2026-12-17**. Keep committing steadily until
then, since the rule asks for continuous development, not only an old repo. Pick the
day once Phase 0 is done, on a Tuesday or Wednesday you can spend replying.

The order is:

1. Release streaks and practice mode. Done: v0.9.0.
2. Quiet announcement (Phase 1), now.
3. Build and release web runs, before 2026-12-17.
4. Finish Phase 0.
5. Launch on r/neovim (Phase 2) on or after 2026-12-17, then go wider a week later
   (Phase 3).
6. Long tail (Phase 4).

The awesome-neovim PR
([#2587](https://github.com/rockerBOO/awesome-neovim/pull/2587)) is already open
and doesn't depend on any of this.

## Principles

- **Launch the game, not a release.** Lead with "a Vim puzzle game scored on
  par", not "v0.5.0 is out". Show HN says routine releases don't qualify.
- **Lead with the daily.** "Today's puzzle, the same for everyone, share
  your score" gives readers a reason to try it now and something to post
  back in the thread. The copied result line (`vimdojo daily … ★★★ 7 keys
  (par 7)`) is spoiler-free by design, so replies can compare scores
  without giving solutions away.
- **One community at a time.** Post in the friendliest, best-fitting place
  first (r/neovim), fix what it finds, then go wider. Don't cross-post the
  same text to several subreddits on the same day.
- **Be there.** Every channel rewards an author who answers questions for the
  first few hours. Don't post when you can't stay.
- **Your words, and be upfront about AI.** HN forbids generated text, and
  dev.to and Medium require disclosure of AI assistance, so rewrite the
  drafts in your own voice.
  - AI-built plugins are a live argument on r/neovim right now (see
    channels.md).
  - Decide before Phase 1 how you'll describe the role AI played in
    building vimdojo, and say it in your first post or comment, without
    waiting to be asked.
  - The CI-proven levels and the written-down decisions are your evidence
    that it's carefully made.
- **Don't lead with leaderboards.** They're new and only lightly used, and an empty
  board isn't much of a hook. Keep the post about the game and the daily, and mention
  boards once as optional. If asked, say that a server replays each run to verify the
  key count, and that offline stays the default.

## Phase 0: prepare (before the r/neovim post)

Done: a current release on LuaRocks, repo metadata, the social preview
(`docs/brand/social-preview.png`), HTTPS on vimdojo.org, Discussions with "Levels"
and "Daily" categories, and Cloudflare Web Analytics. GitHub's Insights → Traffic
keeps views and referrers for only 14 days, so save a screenshot of it a few days
after each post.

Decide the first item before the quiet announcement. Do the rest after web runs, so
they show the final product.

1. **Decide the AI disclosure line.** See Principles and channels.md.
2. **Smoke-test the first-run path** on a machine without your config:
   - lazy.nvim, vim-plug and `:Rocks install vimdojo` installs
   - `:VimDojo`, one level from each track
   - kitty, iTerm2, WezTerm and, if you can, Windows Terminal

   On the demo, check:
   - keyboard focus on load
   - CPU use while idle
   - what a phone shows (earlier Vim-trainer threads on HN complained about
     all three)
3. **Update the posts and the article.** They're written for v0.5.0 (84 levels, 16
   packs). Correct the numbers, and add daily boards, streaks, practice mode and web
   runs. Keep to the leaderboard advice in Principles.
4. **Record a second clip that shows what's new.** The README GIF shows two
   Basic Motions levels. Make a 20 to 40 second clip, as MP4 for Reddit and
   Bluesky and GIF for the README, that shows:
   - the daily at the top of the menu, solved under par, and `y` copying
     the result line,
   - a Setup level: a broken `init.lua`, the diagnostic on the bad line, the
     fix, and the level solving itself.

   `docs/demo.tape` (VHS) can be copied for this. Keep it silent with no
   captions over the editor, so the keys stay readable.
5. **Publish the article on your own blog** (or keep it ready). It's the
   canonical copy for the dev.to and Hashnode cross-posts and the best thing
   to submit to Lobsters.

## Phase 1: quiet announcement (now)

For a first few players before the launch, in places where a small post is normal
and a follow-up isn't a problem.

- **Mastodon and Bluesky**, with the existing GIF and alt text. Mastodon's
  official account is @neovim@hachyderm.io and Bluesky's is @neovim.io. Use hashtags
  rather than @-mentioning them asking for a boost.
- Lead with the daily, and say how AI was used.
- **neovim/neovim Discussions, "Show and tell"**, with the parent/child RPC and sandbox
  details that interest Neovim developers. Read its rules first.
- r/neovim isn't an option yet: see Rule 10 above.

## Phase 2: r/neovim (on or after Thursday 2026-12-17)

- **r/neovim** with the `Plugin` flair and the clip as native media.
  - Post between 08:00 and 13:00 UTC. In the archive, Tuesday and Wednesday
    plugin posts did best and Friday did worst. That's a noisy sample, so
    treat it as a tiebreaker.
  - If the post doesn't appear in "new" (AutoModerator holds posts from
    low-karma accounts), message the mods; don't repost.
  - A realistic outcome for a learning tool there is 20 to 70 points.
    Precognition.nvim's roughly 286 is the high end.
- **Same day:** a Mastodon and Bluesky post with the new clip and alt text.
- **Spend the first four to six hours replying.** Fix what's quick, and cut a patch
  release within a few days if real bugs show up.

## Awesome lists (not tied to a phase)

- **awesome-neovim:** [PR open](https://github.com/rockerBOO/awesome-neovim/pull/2587),
  under `## Game`. Dotfyle, Neovimcraft and the weekly Track Awesome List digest all
  pull from it. Reply to any review comments.
- Skip akrawchyk/awesome-vim for now. It hasn't merged anything since June
  2025, and similar PRs are sitting open. vim-galore is dormant.

## Phase 3: wider launch (a week after r/neovim)

Wait a week after r/neovim, so the obvious bugs are fixed and you can
mention what changed.

- **Show HN**, linking the browser demo, posted from an established personal
  HN account.
  - HN is currently restricting Show HNs from accounts that aren't active
    contributors yet. If yours is new, comment normally for a few weeks
    first, or skip HN this round.
  - Post your first comment within minutes.
  - Don't ask anyone to upvote. HN detects voting rings, and it's against
    the rules.
  - If it doesn't get traction, let it go. HN's FAQ tolerates a small
    number of reposts of a story that got no attention, but never delete
    and repost.
- **Console.dev:** email hello@console.dev with a two-line pitch and the
  links. They feature pre-1.0 developer tools, which vimdojo is.

## Phase 4: long tail (the week after that, onwards)

- **dev.to** (tags `vim`, `neovim`, `showdev`, `opensource`) and **Hashnode**:
  cross-post the article with the canonical URL set to your blog. Disclose AI
  assistance as their policies require, if any of the final text is
  AI-drafted.
- **Lobsters**, if you have an account or can get an invite: submit the
  article, or a write-up about the Setup sandbox or par finding. Tag it `vim`
  plus `show` or `education`. Lobsters prefers write-ups to announcements and
  keeps self-promotion to under a quarter of your activity.
- **r/vim:** it has a "No Neovim only content" rule. Post only with the
  browser demo and the Motions curriculum as the lead, or skip it.
- **r/commandline:** optional, with the `Fun` flair, and only with a plain
  statement of how AI was used (its rules ban undisclosed or unreviewed
  AI-generated projects).
- **YouTube creators:** don't cold-DM. The awesome-neovim listing and a
  well-received r/neovim post are where they find plugins. If someone asks
  for a contact, typecraft (beginner Neovim) and ThePrimeagen (vim-be-good)
  are the most natural fits. One short, polite email with the demo link is
  the ceiling.
- **Later releases:** every new pack is a reason for a short r/neovim post
  ("vimdojo now has a Folding pack"). Keep them at least a few weeks apart.

## Handling feedback

Before launch day, have answers ready for the questions that came up on
earlier Vim-trainer threads:

- **"Why not vimtutor?"** vimtutor explains; vimdojo is practice with a
  score, and it covers Neovim's built-ins and config.
- **"Is the browser version accurate?"** No, it's a taste. It uses
  CodeMirror's emulation, and only levels whose solutions pass there are in
  the demo. The plugin runs real Neovim.
- **"How is this different from VimGolf / vim-be-good?"**
  - Credit both: VimGolf is the inspiration for scoring on keystrokes.
  - The differences:
    - a curriculum where par only uses what's been taught
    - every level in a clean Neovim
    - the Usage and Setup tracks
- **"Leaderboards?"** Yes, optional and off by default: `online = { enabled = true }`,
  then `:VimDojo login`. A server replays each run in a clean Neovim and recounts the
  keys, so boards only show what it can reproduce. They work inside Neovim
  (`:VimDojo board`) and at vimdojo.org/boards. No email or password, and your keys
  stay private. Setup levels aren't ranked, because their checks can still be forged.

How to handle what comes in:

- **Beaten pars and bugs:**
  - Thank the reporter publicly.
  - Fix with a test.
  - Credit them in CHANGELOG.md.
  - Reply in the thread when it's fixed. That reply is worth more than the
    original post.
- **Level ideas:** ask the person to open an issue, or point them to
  docs/authoring-levels.md. Levels are JSON, and CI checks the par.
- **Criticism:**
  - Answer the substance once, plainly, and don't argue the rest.
  - Don't edit a post to rebut comments.
  - Don't comment on downvotes.
- **Keep a launch log** in an issue or a scratch file: where each piece of
  feedback came from, and what you did about it. It makes the next post
  ("thanks to r/neovim, vimdojo now…") easy to write.

## Checklist

- [x] A current release tagged, on LuaRocks, with release notes
- [x] Repo description, website and topics set
- [x] vimdojo.org serves over HTTPS (Enforce HTTPS on)
- [x] Discussions enabled and linked from the README and the site
- [x] Outside contributors' workflow runs need approval
- [x] Social preview image uploaded (`docs/brand/social-preview.png`)
- [x] "Levels" and "Daily" discussion categories added
- [x] Cloudflare Web Analytics merged and deployed
- [x] awesome-neovim PR opened
- [ ] awesome-neovim PR merged
- [x] Streaks and practice mode released (v0.9.0)
- [ ] AI disclosure line decided
- [ ] Quiet announcement on Mastodon and Bluesky
- [ ] neovim/neovim Discussions, Show and tell
- [ ] Web runs released
- [ ] Fresh-install smoke test passed; demo checked for focus, CPU and mobile
- [ ] Manual terminal check: kitty, iTerm2, WezTerm, Windows Terminal
- [ ] Posts and article updated from v0.5.0
- [ ] Second clip recorded (the daily with `y`, plus a Setup level)
- [ ] Article published on your blog
- [ ] Launch date picked
- [ ] r/neovim post, on or after 2026-12-17 (Rule 10)
- [ ] Mastodon and Bluesky post with the new clip
- [ ] Show HN, first comment posted
- [ ] Console.dev email
- [ ] dev.to and Hashnode cross-posts with canonical URL
- [ ] Lobsters (if invited)
