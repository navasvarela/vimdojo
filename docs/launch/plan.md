# Launch plan

The goal is for Neovim and Vim users to hear about vimdojo once, from a post
that's easy to try, and for the first wave of feedback to turn into fixes and
new levels. Channel rules and sources are in [channels.md](channels.md); the
drafts are in [posts.md](posts.md) and [article.md](article.md).

Dates below assume v0.4.0 ships this week (week of 2026-10-19). Shift them
together if it slips.

## Principles

- **Launch the game, not a release.** Lead with "a Vim puzzle game scored on
  par", not "v0.4.0 is out". Show HN says routine releases don't qualify.
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
- **Don't promise what isn't built.** There are no accounts, servers or
  leaderboards. If asked, say so; don't hint at a roadmap you haven't
  committed to.

## Phase 0: prepare (before the first post)

Do these in order; the first four are quick and visible on every link
preview.

1. **Ship v0.4.0.** Tag it, check the LuaRocks upload, and write GitHub
   release notes from CHANGELOG.md. The Setup track is the most distinctive
   feature, so launch after it's released, and make sure the README, the demo
   page and the posts all say 84 levels.
2. **Fill in the GitHub repo metadata.** It's empty right now (no
   description, homepage or topics), which hurts GitHub search and link
   previews.
   - Description: "Learn Vim motions by solving tiny puzzles, right inside
     Neovim. Scored on keystrokes against par."
   - Website: https://navasvarela.github.io/vimdojo/
   - Topics: `neovim`, `neovim-plugin`, `vim`, `lua`, `game`, `puzzle-game`,
     `learning`, `vim-motions`
3. **Upload a social preview image** (Settings → Social preview, 1280×640):
   the torii logo, the name and the one-line tagline on a dark background.
   Reddit, Mastodon, Bluesky and Slack use it when someone pastes the repo
   link.
4. **Give feedback a home.** Enable GitHub Discussions (it's off) or add two
   issue templates: "Level idea" and "I beat a par". Link it from the README
   and the posts, so feedback lands in one place.
5. **Record a second clip that shows what's new.** The README GIF shows two
   Basic Motions levels. Make a 20 to 40 second clip, as MP4 for Reddit and
   Bluesky and GIF for the README, that shows:
   - a level solved under par (e.g. `Gw` on the first level), and
   - a Setup level: a broken `init.lua`, the diagnostic on the bad line, the
     fix, and the level solving itself.

   `docs/demo.tape` (VHS) can be copied for this. Keep it silent with no
   captions over the editor, so the keys stay readable.
6. **Smoke-test the first-run path** on a machine without your config:
   - lazy.nvim, vim-plug and `:Rocks install vimdojo` installs
   - `:VimDojo`, one level from each track
   - Windows, if you can

   On the demo, check:
   - keyboard focus on load
   - CPU use while idle
   - what a phone shows (earlier Vim-trainer threads on HN complained about
     all three)
7. **Publish the article on your own blog** (or keep it ready). It's the
   canonical copy for the dev.to and Hashnode cross-posts and the best thing
   to submit to Lobsters.

## Phase 1: soft launch (Tuesday 2026-10-27)

- **r/neovim** with the `Plugin` flair and the clip as native media.
  - Post between 08:00 and 13:00 UTC. In the archive, Tuesday and Wednesday
    plugin posts did best and Friday did worst. That's a noisy sample, so
    treat it as a tiebreaker.
  - If the post doesn't appear in "new" (AutoModerator holds posts from
    low-karma accounts), message the mods; don't repost.
  - A realistic outcome for a learning tool there is 20 to 70 points.
    Precognition.nvim's roughly 286 is the high end.
- **Same day:** the Mastodon/Bluesky thread, with alt text on the clip.
  Mastodon's official account is @neovim@hachyderm.io and Bluesky's is
  @neovim.io. Use hashtags rather than @-mentioning them asking for a boost.
- **Next day:** a post in the "Show and tell" category of neovim/neovim
  GitHub Discussions, with the parent/child RPC and sandbox details that
  interest Neovim developers.
- **Spend the first four to six hours replying.** Fix what's quick, and cut
  v0.4.1 within a few days if real bugs show up.

## Phase 2: awesome lists (week of 2026-10-26)

- **awesome-neovim** PR, under `## Game`. The list wants plugins to be at
  least a week old, and the repo was created on 2026-10-17. This is the
  highest-value, lowest-risk step. Dotfyle, Neovimcraft and the weekly Track
  Awesome List digest all pull from it.
- Skip akrawchyk/awesome-vim for now. It hasn't merged anything since June
  2025, and similar PRs are sitting open. vim-galore is dormant.

## Phase 3: wider launch (Tuesday 2026-11-03 or Wednesday 2026-11-04)

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

## Phase 4: long tail (week of 2026-11-09 onwards)

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
- **"Leaderboards?"** Not today: there are no servers or accounts, and
  progress stays on your machine.

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

- [ ] v0.4.0 tagged, on LuaRocks, release notes written
- [ ] Repo description, website and topics set
- [ ] Social preview image uploaded
- [ ] Discussions enabled or issue templates added
- [ ] Second clip recorded (beat par + a Setup level)
- [ ] Fresh-install smoke test passed; demo checked for focus, CPU and mobile
- [ ] AI disclosure line decided
- [ ] Article published on your blog
- [ ] r/neovim post (Tue 2026-10-27)
- [ ] Mastodon/Bluesky thread
- [ ] neovim/neovim Discussions, Show and tell
- [ ] awesome-neovim PR (week of 2026-10-26)
- [ ] Show HN (2026-11-03 or 11-04), first comment posted
- [ ] Console.dev email
- [ ] dev.to and Hashnode cross-posts with canonical URL
- [ ] Lobsters (if invited)
