# Channels

Where to announce vimdojo, and how each place works. Researched on
2026-10-19. Every claim links its source. Anything marked *unverified*
couldn't be confirmed (for example because Reddit blocks automated reading),
so check it yourself before posting.

The order and timing are in [plan.md](plan.md), and the drafts are in
[posts.md](posts.md).

## Summary

| Channel | Fit | When | Main rule to respect |
|---|---|---|---|
| r/neovim | Best | Phase 1 | `Plugin` flair, a GIF or video, say how AI was used |
| awesome-neovim | Best (lasting) | Phase 2, repo ≥ 1 week old | Strict line format, one PR per plugin |
| neovim/neovim Discussions, "Show and tell" | Good | Phase 1 | Official forum. Be technical. |
| Mastodon / Bluesky | Good | Phase 1 | Alt text, CamelCase hashtags |
| Show HN | Good, high variance | Phase 3 | Established account, no generated text, be there |
| Console.dev | Good | Phase 3 | Pre-1.0 developer tools only |
| dev.to / Hashnode | Medium | Phase 4 | Canonical URL, AI disclosure |
| Lobsters | Medium | Phase 4 | Invite only, self-promo under 25% |
| r/vim | Weak | Phase 4 | "No Neovim only content" |
| r/commandline | Weak | Optional | No undisclosed AI-generated projects |
| r/programming, r/learnprogramming | Don't | — | Demo and showcase bans |
| This Week in Neovim | Dormant | — | Last issue was January 2025 |
| Neovim Discourse | Gone | — | Replaced by GitHub Discussions |

## The issue that cuts across channels: AI

How a project was built is now one of the first things Neovim readers ask
about.

- **r/neovim:**
  - A "no AI slop plugins" proposal reached about 400 points in August 2026,
    and a moderator said the mods would discuss a policy
    ([thread](https://reddit.com/r/neovim/comments/1vyw06h/how_about_a_no_ai_slop_plugins_policy_here/)).
    Whether a rule was adopted is *unverified*.
  - In October 2026, a plugin post titled "hand-written code with zero AI
    assistance" got 184 points
    ([post](https://reddit.com/r/neovim/comments/1x6nuin/whatsappnvim_handwritten_code_with_zero_ai/)).
- **r/commandline** bans largely AI-generated projects that are low quality
  or unreviewed
  ([mod post](https://reddit.com/r/commandline/comments/1qn8w2r/what_do_you_think_of_flairs_to_indicate_if_a/)).
- **HN** says "Please don't put generated text in HN posts"
  ([guidelines](https://news.ycombinator.com/newsguidelines.html)).
- **dev.to** requires AI-assisted articles to say so
  ([guidelines](https://dev.to/guidelines-for-ai-assisted-articles-on-dev)).
- **Medium** limits unlabelled AI-assisted stories to the author's network
  ([policy](https://help.medium.com/hc/en-us/articles/22576852947223-Artificial-Intelligence-AI-content-policy)).

**Recommendation:**

- Decide before launch how you'll describe the role AI played in building
  vimdojo, and say it plainly in the first post or first comment, without
  waiting to be asked.
- Rewrite the drafts in your own voice either way.
- The strongest answer to "is this AI slop?" is evidence:
  - every level is proven in real Neovim in CI (0.10.4, stable, nightly and
    Windows);
  - the design decisions are written down in `docs/decisions.md`;
  - you're answering questions yourself.
- Being caught out later costs far more than saying it up front.

## Reddit

Reddit blocked direct reading. Rules come from January 2025 snapshots in
the Arctic Shift archive
([rules](https://arctic-shift.photon-reddit.com/api/subreddits/rules?subreddits=neovim,vim,commandline,programming,learnprogramming)),
and post data from the same archive is current to October 2026. **Re-read
each sidebar before posting:** the current wording is *unverified*.

### r/neovim (about 2,850 posts from March to October 2026)

- **Rules:**
  - "No low-effort content": titles should include useful context.
  - "No soliciting/spamming/selling."
  - "No plagiarism."
  - Monthly threads are for dotfiles and memes.
  - There's no 9:1 ratio rule and no plugin-promotion thread, so plugin
    announcements are normal top-level posts.
- **Flair:** `Plugin`. Others in use include `Video` and `Tips and Tricks`
  ([recent posts](https://arctic-shift.photon-reddit.com/api/posts/search?subreddit=neovim&after=2026-08-01&limit=100)).
  Images and video are allowed.
- **Format:** "name - one-line description" titles, with a GIF or video.
  - The hardtime.nvim author's advice: posts with a GIF get more clicks; put
    the details in a comment; don't post minor updates
    ([dev.to](https://dev.to/m4xshen/how-i-grew-my-open-source-project-to-1k-stars-3mk2)).
- **Precedent:**
  - The archive is
    [here](https://arctic-shift.photon-reddit.com/api/posts/search?subreddit=neovim&after=2026-03-01&limit=100).
    Scores are archive snapshots, so treat them as approximate.
  - **Plugin posts in general** (n=914, March to October 2026): the median
    score is 5, about 18% reach 50 and 8% reach 100.
  - **Learning tools usually land at 20 to 70 points:**
    - [precognition.nvim v1.0](https://reddit.com/r/neovim/comments/1dc22uc/precognition_v10_ready_for_ga/)
      got about 286 and was praised as a way to learn motions.
    - [BobaVim](https://reddit.com/r/neovim/comments/1mazb14/just_launched_bobavim_a_browser_game_to_learn_and/)
      got 54. Its top criticism was needing an account.
    - [vim-norm-trainer.nvim](https://reddit.com/r/neovim/comments/1ri7m5f/vimnormtrainernvim_train_your_norm_skills_in/)
      got 19, with a request for saved progress, which vimdojo has.
- **Timing:**
  - Archive analysis of Plugin posts (noisy, effectively anecdotal):
    - **By day:** Tuesday and Wednesday did best (median 12); Friday did
      worst (median 1).
    - **By hour:** posts at 06:00 to 11:00 UTC did a little better; 21:00 to
      02:00 UTC did worst.
  - **Aim for Tuesday, 08:00 to 13:00 UTC.**
- **New accounts:** many game posts were caught by AutoModerator when first
  posted, which suggests karma or account-age filters (thresholds
  *unverified*). If your post doesn't show up in "new", message the mods
  politely rather than reposting.

### r/vim (about 440 posts from March to October 2026)

- Same base rules, plus **"No Neovim only content"**: "Unless you are
  confident your post applies to both vim and Neovim, please use r/neovim."
  ([rules](https://arctic-shift.photon-reddit.com/api/subreddits/rules?subreddits=vim))
- vimdojo the plugin is Neovim-only. The browser demo and the Motions
  curriculum do apply to Vim, so lead with those or don't post.
- Plugin posts rarely do well there: 1 of 55 reached 50 points.
- Precedent:
  - [BobaVim](https://reddit.com/r/vim/comments/1mazaic/just_launched_bobavim_a_browser_game_to_learn_and/)
    got 49 the same day as its r/neovim post; posting to both subs on the
    same day was fine.
  - A [Tetris-finesse Vim game](https://reddit.com/r/vim/comments/1n7mdog/hey_i_built_a_tetris_finesse_inspired_vim_game/)
    got comments asking to see the fewest-keystroke solution afterwards.
    That's vimdojo's par idea, so it's worth mentioning.

### r/commandline

- Rules: direct URLs only, and no blogspam
  ([rules](https://arctic-shift.photon-reddit.com/api/subreddits/rules?subreddits=commandline)).
- Since January 2026, projects that are largely AI-generated (low quality
  or unreviewed) are banned
  ([mod post](https://reddit.com/r/commandline/comments/1qn8w2r/what_do_you_think_of_flairs_to_indicate_if_a/)).
- Flairs: `Fun`, `Terminal User Interface`.
- It's a secondary fit, because it's a Neovim plugin rather than a CLI tool.

### r/programming and r/learnprogramming: skip

- r/programming:
  - Direct links to app demos are removed, and accounts that are mostly
    self-promotion are banned.
  - LLM-generated text is banned
    ([announcement](https://reddit.com/r/programming/comments/1s9jkzi/announcement_temporary_llm_content_ban/)).
  - The only route is a genuinely technical article, such as the Setup
    sandbox write-up, and only after it has stood on its own elsewhere.
- r/learnprogramming bans app showcases and self-promotion from first-time
  posters
  ([rules](https://arctic-shift.photon-reddit.com/api/subreddits/rules?subreddits=learnprogramming)).

## Hacker News (Show HN)

- **Rules** ([Show HN](https://news.ycombinator.com/showhn.html)):
  - It must be something people can try, made by you, and you must be
    around to discuss it.
  - Make it easy to try, ideally with no signup.
  - Asking friends to upvote or comment is not OK.
  - Routine releases and new features usually don't qualify. Present the
    game itself.
- **Title** ([guidelines](https://news.ycombinator.com/newsguidelines.html)):
  starts with "Show HN:", no uppercase or exclamation marks for emphasis, no
  editorializing.
- **Generated text:** "Please don't put generated text in HN posts."
- **New accounts:** Show HN is currently restricted for accounts that aren't
  established contributors yet ([notice](https://news.ycombinator.com/showlim)).
  - The moderator dang confirmed on 2026-10-02 that the restriction still
    applies ([comment](https://news.ycombinator.com/item?id=49938039)).
  - The thresholds aren't published.
- **First comment:** dang repeatedly advises authors to add the backstory and
  what's different
  ([1](https://news.ycombinator.com/item?id=22515402),
  [2](https://news.ycombinator.com/item?id=19374834),
  [tips](https://news.ycombinator.com/item?id=22336638)). Don't use the
  project name as your username.
- **Precedent** (from HN Algolia search):

  | Post | Points |
  |---|---|
  | [vim.so](https://news.ycombinator.com/item?id=25846347) (2021) | 667 |
  | [vimified](https://news.ycombinator.com/item?id=32034625) (2022) | 344 |
  | [Vim Adventures "as RPG"](https://news.ycombinator.com/item?id=32950623) (2022) | 78 |
  | [Vimgolf.ai](https://news.ycombinator.com/item?id=49095143) (July 2026) | 36 |
  | [Golf.vim](https://news.ycombinator.com/item?id=43674438), a daily-challenge plugin | about 3 |

  Expect wide variance.
- **What comments keep raising:**
  - paywalls and signups (heavily criticised)
  - "why not vimtutor?"
  - doubts about browser emulation accuracy
  - focus not set on load, high CPU, overwhelming animation
  - recommendations of VimGolf and vim-be-good

  Free, no signup and real Neovim are vimdojo's answers. Frame the browser
  demo as a taste.
- **Timing:** no reliable data. Weekday mornings US time are the common
  advice ([anecdotal](https://feedbagel.com/post/optimal-posting-time-on-show-hn-revealed-through-data-analysis)).
  Being available matters more.

## Lobsters

- **Membership:** invitation only. Ask someone you know there, or ask in
  chat ([about](https://lobste.rs/about)).
- **Self-promotion:**
  - Should be under a quarter of your stories and comments.
  - Lobsters doesn't want to be "a write-only tool for product
    announcements".
  - Tick "I am the author" when you submit.
- **Accounts younger than 70 days can't:**
  - use the `show`, `announce` or `ask` tags;
  - submit domains Lobsters hasn't seen before. `vimdojo.org` hasn't been
    submitted before ([domain page](https://lobste.rs/domains/vimdojo.org)
    is a 404), so link GitHub instead.
- **Tags** ([tags.json](https://lobste.rs/tags.json)): `vim` (there's no
  `neovim` tag; Neovim stories use `vim`), `show`, `games`, `education`,
  `editors`, `lua`, `release`.
- **Best fit:** a technical write-up (the article, or a post about the Setup
  sandbox), rather than the repo.

## awesome-neovim

- **The list:** [rockerBOO/awesome-neovim](https://github.com/rockerBOO/awesome-neovim).
  It's very active, with "Add" PRs merged daily in October 2026.
- **Rules**
  ([CONTRIBUTING](https://github.com/rockerBOO/awesome-neovim/blob/main/CONTRIBUTING.md),
  [PR template](https://github.com/rockerBOO/awesome-neovim/blob/main/.github/pull_request_template.md)):
  - PR title ``Add `navasvarela/vimdojo` ``, which a workflow checks.
  - One plugin per PR, and keep the template.
  - The description:
    - ends with `.`
    - has no emojis
    - avoids the words "plugin" and "Neovim"
    - doesn't say "for Neovim"
    - spells `Neovim`, `Vim` and `Lua` exactly that way
  - Run `./scripts/readme-check.sh` before submitting.
- **Acceptance**
  ([MAINTAINERS](https://github.com/rockerBOO/awesome-neovim/blob/main/MAINTAINERS.md#acceptance-criteria)):
  - Neovim-specific, working, open-source licence.
  - A README with install and usage instructions.
  - Maintained.
  - **At least a week old.** The repo was created on 2026-10-17, so it's
    eligible from 2026-10-24.
- **Section:** [`## Game`](https://github.com/rockerBOO/awesome-neovim#game),
  alongside nvim-tetris, nvimesweeper and playtime.nvim. (hardtime.nvim is
  under Workflow and precognition.nvim under Motion. vim-be-good isn't
  listed.)
- **Knock-on listings:** the list feeds the
  [Dotfyle](https://github.com/codicocodes/dotfyle/blob/main/CONTRIBUTING.md)
  seeder and [Neovimcraft](https://github.com/neurosnap/neovimcraft#readme),
  and the weekly
  [Track Awesome List](https://www.trackawesomelist.com/rockerBOO/awesome-neovim/week/)
  digest. One PR covers all three.
- **Other lists:**
  - [akrawchyk/awesome-vim](https://github.com/akrawchyk/awesome-vim) has a
    "Learning Vim" section, but its last merge was in June 2025 and similar
    PRs sit open. Low value.
  - [vim-galore](https://github.com/mhinz/vim-galore) has been dormant
    since 2023.

## Dotfyle and newsletters

- **Dotfyle** lists plugins found in uploaded configs and seeds from
  awesome-neovim ([README](https://github.com/codicocodes/dotfyle#readme)).
  There's also a manual form at https://dotfyle.com/neovim/plugins/add
  (GitHub login).
- **This Week in Neovim:** dormant. The last issue is #80, from 2025-01-06
  ([archive](https://dotfyle.com/this-week-in-neovim)), and its contents repo
  is gone.
- **Console.dev:**
  - Active, with an issue on 2026-10-15.
  - Suggestions go by email to hello@console.dev.
  - It features beta or pre-1.0 developer tools
    ([criteria](https://console.dev/selection-criteria)), which vimdojo is.
- **Changelog News:** has a [submit form](https://changelog.com/news/submit),
  but may be paused (the last issue was 2026-04-29). Low priority.
- **Dead or unverified:** VimTricks has been dead since 2022. Nat's Neovim
  Newsletter is *unverified* as active.
- **Terminal Trove** ([submit](https://terminaltrove.com/post/)) lists
  standalone terminal tools, not Neovim plugins. Skip it.

## Official Neovim spaces

- **Discourse:** `neovim.discourse.group` no longer resolves. neovim.io now
  points to GitHub Discussions, Matrix, IRC and vi.stackexchange
  ([PR #351](https://github.com/neovim/neovim.github.io/pull/351)).
- **neovim/neovim GitHub Discussions** has a
  [Show and tell](https://github.com/neovim/neovim/discussions/categories/show-and-tell)
  category ("Show off something you've made"), where people post plugins,
  for example
  [this one from October 2026](https://github.com/neovim/neovim/discussions/42283).
  It's the best official place.
- **Matrix #neovim:matrix.org:** its promotion rules are *unverified*. Treat
  it as a help channel; don't drop announcements there.
- **vi.stackexchange:** not an announcement venue. Self-promotion must be
  disclosed and is flagged as spam when overt
  ([policy](https://vi.stackexchange.com/help/promotion)).

## Mastodon, Bluesky, X

- **Official Neovim accounts** (linked from [neovim.io](https://neovim.io/)):
  - Mastodon: @neovim@hachyderm.io
  - Bluesky: @neovim.io
  - X: [@Neovim](https://x.com/Neovim)

  (@neovim@fosstodon.org doesn't exist.)
- **Hashtags:** `#Neovim` and `#Vim` are active but small (about one or two
  posts a day on
  [fosstodon](https://fosstodon.org/tags/neovim)). Fosstodon bans commercial
  promotion; a free MIT tool is likely fine (*unverified*).
- **Norms:**
  - CamelCase hashtags, so screen readers read them correctly
    ([fedi.tips](https://fedi.tips/?p=4247)).
  - Alt text on every image and GIF ([fedi.tips](https://fedi.tips/?p=1187)).
  - Bluesky posts are limited to 300 characters. The drafts fit.

## Blogs: dev.to, Hashnode, Medium

- **dev.to:**
  - Up to four tags. `#vim`, `#neovim`, `#showdev` ("not overly corporate
    or salesy") and `#opensource` all exist.
  - `canonical_url` goes in the front matter
    ([editor guide](https://dev.to/p/editor_guide),
    [showdev](https://dev.to/t/showdev)).
  - AI-assisted posts must say so
    ([guidelines](https://dev.to/guidelines-for-ai-assisted-articles-on-dev)).
  - A similar post ("I built a Vim trainer with AI") went up on 2026-10-14
    ([post](https://dev.to/s3onghyun/i-can-barely-use-vim-so-i-built-a-vim-trainer-with-ai-then-i-failed-my-own-level-4aid)).
    Expect comparisons.
- **Hashnode:** set the canonical link with "Are you republishing? → Add
  Original URL"
  ([docs](https://docs.hashnode.com/help-center/hashnode-editor/how-to-set-a-canonical-link)).
- **Medium:**
  - "Import a story" sets the canonical link
    ([help](https://help.medium.com/hc/en-us/articles/214550207)).
  - AI-assisted stories must be labelled
    ([policy](https://help.medium.com/hc/en-us/articles/22576852947223-Artificial-Intelligence-AI-content-policy)).
  - Lowest priority of the three.

## YouTube creators

There's no public "suggest a plugin" route for any of them (*unverified*),
and cold DMs read as spam. They find plugins on r/neovim and awesome-neovim.
If you do write, send one short email with the demo link.

| Creator | Channel | Why they fit |
|---|---|---|
| ThePrimeagen | [@ThePrimeagen](https://www.youtube.com/@ThePrimeagen) | Wrote [vim-be-good](https://github.com/ThePrimeagen/vim-be-good) |
| TJ DeVries | [@teej_dv](https://www.youtube.com/@teej_dv) | Neovim core team member who streams |
| typecraft | [@typecraft_dev](https://www.youtube.com/@typecraft_dev) | Beginner Neovim content, the closest audience match |
| Dreams of Code | [@dreamsofcode](https://www.youtube.com/@dreamsofcode) | Dev tooling, Neovim setups |
| Vhyrro | [@vhyrro](https://www.youtube.com/@vhyrro) | "Understanding Neovim" series |
| Josean Martinez | [@joseanmartinez](https://www.youtube.com/@joseanmartinez) | Neovim and terminal setups |
