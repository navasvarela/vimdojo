# Launch plan

The goal is for Neovim and Vim users to hear about vimdojo once, from a post
that's easy to try, and for the first wave of feedback to turn into fixes and
new levels. Channel rules and sources are in [channels.md](channels.md); the
drafts are in [posts.md](posts.md) and [article.md](article.md).

v0.5.0 shipped on 2026-10-30 with the daily challenge and shareable
results, and vimdojo.org has served over HTTPS since 2026-10-24. The dates
below give the rest of Phase 0 until Monday 2026-11-02. If prep takes
longer, move all the dates together.

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
- **Don't promise what isn't built.** There are no accounts, servers or
  leaderboards yet. A design for opt-in, verified leaderboards is in
  `docs/proposals/leaderboard-and-community.md`, but nothing is scheduled.
  If asked, say it's being considered, that offline stays the default, and
  ask what they'd want from it. Don't give dates.

## Phase 0: prepare (before the first post)

Do these in order; the first four are quick and visible on every link
preview.

1. **Ship a current release.** Done: v0.5.0 is tagged, on LuaRocks, with
   release notes and a changelog that covers the landing refresh and the
   move to vimdojo.org.
2. **Fill in the GitHub repo metadata.** Done: the description, website
   (https://vimdojo.org) and topics (`neovim`, `neovim-plugin`, `vim`,
   `lua`, `game`, `puzzle-game`, `learning`, `vim-motions`) are set.
3. **Upload the social preview image** (Settings → General → Social
   preview): `docs/brand/social-preview.png`, 1280×640, with the torii
   logo, the name and the tagline. Reddit, Mastodon, Bluesky and Slack use
   it when someone pastes the repo link. GitHub has no API for this.
4. **Give feedback a home.** Discussions are on and linked from the README
   and the site. Add two categories in the web UI (the API can't create
   them): "Levels" (ideas and beaten pars, discussion format) and "Daily"
   (one thread per day's puzzle, solutions in spoiler blocks). Then link
   Discussions from the posts.
5. **Record a second clip that shows what's new.** The README GIF shows two
   Basic Motions levels. Make a 20 to 40 second clip, as MP4 for Reddit and
   Bluesky and GIF for the README, that shows:
   - the daily at the top of the menu, solved under par, and `y` copying
     the result line,
   - a Setup level: a broken `init.lua`, the diagnostic on the bad line, the
     fix, and the level solving itself.

   `docs/demo.tape` (VHS) can be copied for this. Keep it silent with no
   captions over the editor, so the keys stay readable.
6. **HTTPS on vimdojo.org.** Done: the certificate covers `vimdojo.org`
   and `www.vimdojo.org`, Enforce HTTPS is on, and both `http://vimdojo.org`
   and the old github.io address redirect to `https://vimdojo.org/`.
7. **Smoke-test the first-run path** on a machine without your config:
   - lazy.nvim, vim-plug and `:Rocks install vimdojo` installs
   - `:VimDojo`, one level from each track
   - Windows, if you can

   On the demo, check:
   - keyboard focus on load
   - CPU use while idle
   - what a phone shows (earlier Vim-trainer threads on HN complained about
     all three)
8. **Publish the article on your own blog** (or keep it ready). It's the
   canonical copy for the dev.to and Hashnode cross-posts and the best thing
   to submit to Lobsters.
9. **Measure.** Merge the Cloudflare Web Analytics PR before the first
   post, so launch traffic on vimdojo.org is counted (cookieless, no
   banner). GitHub's Insights → Traffic keeps views and referrers for only
   14 days, so save a screenshot of it a few days after each post.

## Phase 1: soft launch (Tuesday 2026-11-03)

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
  v0.5.1 within a few days if real bugs show up.

## Phase 2: awesome lists (any time now)

- **awesome-neovim** PR, under `## Game`. The list wants plugins to be at
  least a week old, and the repo was created on 2026-10-17, so it qualifies
  since 2026-10-24, and the repo metadata is in place. This is the highest-value, lowest-risk step, and it doesn't
  depend on Phase 1. Dotfyle, Neovimcraft and the weekly Track
  Awesome List digest all pull from it.
- Skip akrawchyk/awesome-vim for now. It hasn't merged anything since June
  2025, and similar PRs are sitting open. vim-galore is dormant.

## Phase 3: wider launch (Tuesday 2026-11-10 or Wednesday 2026-11-11)

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

## Phase 4: long tail (week of 2026-11-16 onwards)

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
- **"Leaderboards?"** Not yet. Progress stays on your machine, and there
  are no servers or accounts. Opt-in leaderboards that replay each run to
  verify the key count are designed but not scheduled. Ask what they'd
  want; the daily's share line is the low-tech version for now.

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

- [x] A current release (v0.5.0) tagged, on LuaRocks, with release notes
- [x] Changelog covers the landing refresh and vimdojo.org
- [x] Repo description, website and topics set
- [x] vimdojo.org serves over HTTPS (Enforce HTTPS on)
- [x] Discussions enabled and linked from the README and the site
- [x] Outside contributors' workflow runs need approval
- [ ] Social preview image uploaded (`docs/brand/social-preview.png`)
- [ ] "Levels" and "Daily" discussion categories added
- [ ] Cloudflare Web Analytics merged and deployed
- [ ] Second clip recorded (the daily with `y`, plus a Setup level)
- [ ] Fresh-install smoke test passed; demo checked for focus, CPU and mobile
- [ ] Manual terminal check: kitty, iTerm2, WezTerm, Windows Terminal
- [ ] AI disclosure line decided
- [ ] Article published on your blog
- [ ] r/neovim post (Tue 2026-11-03)
- [ ] Mastodon/Bluesky thread
- [ ] neovim/neovim Discussions, Show and tell
- [ ] awesome-neovim PR (eligible now)
- [ ] Show HN (2026-11-10 or 11-11), first comment posted
- [ ] Console.dev email
- [ ] dev.to and Hashnode cross-posts with canonical URL
- [ ] Lobsters (if invited)
