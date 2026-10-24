# Proposal: leaderboards and community

> Status: **draft for decision**. Research and design only; nothing here is
> built yet. Prices and limits were checked on 2026-10-19 (sources at the
> end) and will drift.

## 1. Summary

vimdojo can get a competitive leaderboard and a community without giving up
what makes it work today: the plugin stays fully usable offline, every online
feature is opt-in, and the small-scale running cost stays at **$0**.

The core idea is to rank what we can actually verify. A finished attempt is
submitted as a **key log**. A verifier replays it in a sandboxed, clean
Neovim (the same engine the solution tests use), checks the goal and
**recomputes the key count**. Keys are the game's main score, and a replay
makes them trustworthy. Time can't be made trustworthy (§5.4), so it is only
a secondary, clearly labelled number, and ties on keys are broken by the
server's own timestamp of who got there first.

Recommended stack: **Vercel Hobby** (static site + Node functions + Vercel
Sandbox for replays) with **DynamoDB** (one table, provisioned at free-tier
capacity) and **GitHub OAuth** (web flow for the browser, device flow for
the plugin). No passwords, no emails, public handles only.

Community levels keep arriving as **pull requests**, through the CI gates
that already exist (schema, solution tests in real rooms, emulation gate),
plus a few new ones for untrusted content and human review for anything that
runs code.

The smallest useful first step needs no backend at all: a daily challenge,
shareable result text, and GitHub Discussions (§10, phase 0).

## 2. Goals and constraints

From the brief, PLAN.md and PLAN-v2.md:

- **Offline first.** The plugin and the web demo work with no network and no
  account, exactly as today. No network call happens unless the player turns
  online features on.
- **Zero or near-zero cost.** Free plans at small scale; tens of dollars a
  month at medium scale, and only if the project grows that far.
- **Minimal personal data.** A public handle, a GitHub numeric id, and game
  results. No emails, no passwords, no IP addresses at rest, no analytics.
- **Honest scores.** A public board only shows results the server can
  reproduce. Where something can't be verified, the UI says so.
- **One source of truth for levels.** `challenges/` stays the data. The
  server and the verifier read it from the same commit; nothing is copied by
  hand.

Non-goals: chat, private messaging, monetization, a mobile app, and
anything that runs player-supplied code on a shared machine outside a
microVM.

## 3. What the current code already gives us

These facts shape the design (see `docs/decisions.md`):

| Fact | Consequence |
|---|---|
| Keys are counted in the parent with `vim.on_key`, one physical key per key, in Vim notation (`keys.lua`, `keys.ts`). | The plugin can record the same keys it counts as a notation log, with no new capture code. |
| Every level runs in a child `nvim --clean` room, and `tests/player.lua` drives that path headlessly. | A server-side replay can use the exact engine the solution tests prove levels with. |
| The game ends at the first moment the goal holds in Normal mode. | A replay can find that moment itself and ignore keys after it. |
| Points cap at 1000 when keys and time are at or under par. | Points are useless for ranking: everyone good ties at 1000. Boards must rank by keys. |
| The hint is plain JSON in the repo. | "Used the hint" is honor-system and can't be verified. |
| `config = "mine"` runs with the player's mappings. | Such runs mean different keys and can't be ranked. |
| Setup levels run the player's `init.lua` in the same Lua state as the probes ("isolation, not a security sandbox", M12). | A hostile config can forge its own probe results. Setup levels can't be verified until probes run out of process (§5.6). |
| The emulation diverges from Neovim in known places (M9/M10 notes). | One arbiter is needed for all sources; Neovim is the natural one. |
| `progress.json` is exportable and shareable. | Credentials must never live in it. |

## 4. Architecture

### 4.1 Components

```
 Neovim plugin ──(curl, opt-in)──┐
                                 │  HTTPS
 Browser (site + demo) ──────────┤
                                 ▼
 ┌──────────────── Vercel project (one origin) ─────────────────┐
 │ static site (Vite build)      /api/v1/* Node functions       │
 │                               ├─ auth (GitHub web + device)  │
 │                               ├─ runs (submit, status)       │
 │                               ├─ boards, profiles, daily     │
 │                               └─ verifier orchestrator ──────┼──► Vercel Sandbox
 │ build step: level manifest (id → content hash, eligibility)  │    (Firecracker microVM,
 └───────────────┬──────────────────────────────────────────────┘     network denied,
                 │ IAM role via Vercel OIDC (no static keys)          pinned Neovim builds +
                 ▼                                                    vimdojo at the same commit)
           DynamoDB (one table, encrypted at rest)

 GitHub: OAuth app (identity) · repo + CI (levels, manifest) · Discussions (community)
```

- **Site and API share one origin** on Vercel. Cookies stay first-party,
  CORS isn't needed, and the CSRF story is simple (§6.5). GitHub Pages can
  redirect to it, or keep serving a static mirror without online features.
- **Functions are thin.** They validate input (zod, as the web already does),
  authenticate, rate-limit, read and write DynamoDB, and enqueue
  verification. They never run Neovim and never execute a key log.
- **The verifier** runs in Vercel Sandbox: a Firecracker microVM per batch,
  booted from a snapshot that holds pinned Neovim binaries (0.10, 0.11 and
  the current stable, matching the CI matrix) and vimdojo at the commit the
  manifest was built from. Its firewall denies all outbound traffic, and it
  holds no credentials. The orchestrating function writes jobs in and reads
  verdicts out.
- **The level manifest** is generated at build time from `challenges/`, the
  same way `web/build/curriculum.ts` renders the curriculum. It maps each
  level id to its **content hash** and says whether the level is ranked
  (§5.2). The deployed API and the verifier snapshot carry the same git SHA.

Suggested layout in the monorepo: `web/api/` (function entry points),
`web/server/` (domain logic, a storage interface and its DynamoDB adapter,
reusing `keys.ts`, `scoring.ts` and the zod level parser from `web/src/`),
and `verifier/` (the trusted harness, a Node RPC client, and the snapshot
build script).

### 4.2 Data model (DynamoDB, single table)

One table keeps the free-tier capacity in one place. Keys are strings;
`uid` is a random ULID, never the GitHub id.

| Entity | PK | SK | Main attributes | Notes |
|---|---|---|---|---|
| User | `USER#<uid>` | `PROFILE` | `handle`, `created_at`, `status` (`active`/`banned`), `eligible` | No email, no GitHub login stored. |
| GitHub link | `GH#<github_id>` | `LINK` | `uid` | Lets a login find its user. Numeric id, because logins can be renamed. |
| Handle | `HANDLE#<lowercased>` | `CLAIM` | `uid` | Written in the same transaction as the profile, with a condition, for uniqueness. |
| Token | `TOKEN#<sha256(token)>` | `TOKEN` | `uid`, `kind` (`web`/`plugin`), `created_at`, `last_used_at`, `expires_at` (TTL) | Only the hash is stored. A copy under `USER#<uid>` / `TOKEN#<id>` lists them for revocation. |
| Device login | `DEVICE#<id>` | `DEVICE` | GitHub `device_code`, `expires_at` (TTL, 15 min) | The plugin never sees the GitHub token. |
| Run | `USER#<uid>` | `RUN#<level_id>#<ulid>` | `level_hash`, `source`, `client`, `nvim`, `log` (compressed), `log_hash`, `claimed` {keys, seconds, hinted}, `status`, `verified_keys`, `received_at`, `expires_at` (TTL 90 days unless it's a best) | `status`: `pending`, `verified`, `mismatch`, `rejected`, `unranked`. |
| Best | `USER#<uid>` | `BEST#<level_hash>` | `keys`, `seconds`, `first_at`, `run_sk`, `hinted` | Updated when a verified run improves on it. |
| Board entry | GSI1 `BOARD#<level_hash>` | GSI1 `<keys:4>#<first_at>#<uid>` | projected `handle`, `keys`, `seconds`, `hinted` | Sparse: only verified, eligible bests carry GSI1 keys. Top N is one `Query`. |
| Pending queue | GSI2 `PENDING` | GSI2 `<received_at>` | | Sparse: removed once verified. |
| Verdict cache | `VERDICT#<level_hash>#<nvim>#<log_hash>` | `VERDICT` | `solved`, `keys`, `checked_at` | Identical logs (very common at par) verify once. |
| Rate counter | `RL#<subject>#<window>` | `RL` | `count`, `expires_at` (TTL) | `subject` is a uid, or a salted IP hash for unauthenticated routes. |
| Daily | `DAILY#<yyyy-mm-dd>` | `DAILY` | `level_id`, `level_hash` | Its board is `BOARD#daily#<date>`. |

"What's my rank" is a `Query` on the board partition with `SK < mine` and
`Select=COUNT`. Its cost grows with the rank, which is fine for boards of a
few thousand entries; past that, cache ranks per level on write. Global
rankings (total stars across levels) are an aggregate item per user updated
when a best changes, with its own sparse GSI, and they come later (phase 2).

### 4.3 API (v1)

All JSON over HTTPS. Bodies are size-capped (16 KB) and schema-validated.
Bearer tokens for the plugin, a session cookie for the browser.

| Method and path | Auth | Purpose |
|---|---|---|
| `GET /api/v1/auth/github/start` | none | Browser login: redirect to GitHub with `state` and PKCE. |
| `GET /api/v1/auth/github/callback` | none | Exchange the code, find or create the user, set the session cookie. |
| `POST /api/v1/auth/device` | none | Plugin login: returns `user_code`, `verification_uri`, `interval`, `device_id`. |
| `POST /api/v1/auth/device/poll` | none | `{device_id}` → `pending`, or a vimdojo token once approved. |
| `POST /api/v1/auth/logout` | any | Revokes the current token or session. |
| `GET /api/v1/me` · `PATCH /api/v1/me` | any | Own profile; change handle. |
| `GET /api/v1/me/tokens` · `DELETE /api/v1/me/tokens/{id}` | any | List and revoke logins ("signed in from the plugin on …"). |
| `GET /api/v1/me/export` | any | Everything stored about the account, as JSON. |
| `DELETE /api/v1/me` | any | Delete the account and all its data (§6.6). |
| `POST /api/v1/runs` | any | Submit a run (below). Idempotent on the client-generated `run_id`. Returns `202` with `status: pending`. |
| `POST /api/v1/attempts` | any | Optional attempt ticket (signed, stateless) when a level opens, used for the server window (§5.4) and the daily. |
| `GET /api/v1/runs/{run_id}` | owner | Verification status and result. |
| `GET /api/v1/levels/{level_id}/board` | none | Top 50 for the level's current hash. Cached at the CDN for 60 s. |
| `GET /api/v1/levels/{level_id}/board/me` | any | Own rank and best. |
| `GET /api/v1/players/{handle}` | none | Public profile: handle, joined month, verified bests. |
| `GET /api/v1/daily` | none | Today's level id and its board. |
| `POST /api/v1/admin/…` | maintainer | Reject a run, ban a user, release a handle. The maintainer list is GitHub ids in an environment variable. |

Run submission:

```json
{
  "run_id": "01JA7…",
  "level_id": "operate-01",
  "level_hash": "sha256:9f2c…",
  "source": "plugin",
  "client": { "version": "0.4.0", "nvim": "0.12.1", "config": "clean" },
  "keys": ["f", "f", "d", "w"],
  "deltas_ms": [0, 180, 240, 95],
  "claimed": { "keys": 4, "seconds": 0.52, "hinted": false }
}
```

- `keys` are Vim key notation, one entry per counted key (`<Esc>`, `<C-r>`,
  `<lt>` for a literal `<`), from the last reset to the solve. Control keys
  (hint, reset, quit) are left out, as the counter already does. Capped at
  2,000 keys.
- `deltas_ms` are the gaps between keys, used for plausibility checks
  (§5.4), never for ranking.
- `level_hash` must be in the deployed manifest. An older hash gets `409
  level_changed` and a hint to update the plugin; a hash we've never seen
  (a custom `challenges_dir`) gets `422 unknown_level`.

## 5. Scores and anti-cheat

### 5.1 Threat summary

Both clients are open source and run on machines the player controls. Lua
can be edited, the browser has devtools, and any HTTP request can be
forged. **Anything a client says is a claim.** Signing requests in the
client doesn't help: the key would be public. What the server can do is
check claims against things it computes itself.

| Claim | Can the server check it? |
|---|---|
| This key sequence solves this level | **Yes**, by replaying it in a clean Neovim. |
| It takes this many keys | **Yes**, by counting the log and finding where the goal is first met. |
| It was this exact level | **Yes**, through the content hash. |
| It was played with stock Neovim | **Yes**: the replay uses stock Neovim, so a mapping-dependent log fails. |
| It took this long | **No.** Only plausibility. |
| A human typed it, live, unaided | **No.** A replay proves a solution exists, not who found it or how. |
| The hint wasn't used | **No.** |

### 5.2 Trust levels

| Level | What it means | Where it shows |
|---|---|---|
| **T0 Local** | `progress.json` or `localStorage`. Never leaves the machine. | The player's own menu, as today. The default. |
| **T1 Submitted** | Received and stored, not (yet) reproduced. | Only the owner's run history. Never on a public board. |
| **T2 Verified keys** | The verifier replayed the log in a clean room on a pinned Neovim, reached the goal, and recomputed the key count. Time is still self-reported but passed plausibility checks. | Public boards, ranked by verified keys. Time is shown with a "self-reported" marker. |
| **T3 Live** *(optional, later)* | T2, plus the start state came from a server seed only revealed when the attempt began (§5.5). | A separate "live" board for the daily challenge. |

Status values map onto these: `pending` (T1), `verified` (T2), `mismatch`
(replay solved it with a different key count; ranked with the verifier's
count), `rejected` (replay didn't solve it), `unranked` (valid but not
eligible: `config = "mine"`, a Setup level, or an emulation-only web run).

**Recommendation: no public unverified boards.** They fill up with
zero-key, zero-second entries within days, and they're what people
screenshot.

**Ranking:** fewest verified keys first, then **earliest `first_at`**, the
server's own timestamp of when this player first reached that key count.
That tie-break is the only one the server can vouch for, and it rewards
finding the short route first. Self-reported time is shown and can sort a
separate "speed" view, labelled as such.

### 5.3 The verifier

Per batch of pending runs (all from **one user**, so a hostile log can only
affect its own owner's results):

1. The orchestrating function checks the verdict cache by
   `(level_hash, nvim, log_hash)`. Most par-level solutions are identical
   and never reach a sandbox.
2. It resumes the verifier sandbox from its snapshot, with the network
   policy set to deny all, and writes one job file per run: the level JSON
   **from the manifest** (never from the client) and the key log.
3. Inside the VM, a **trusted harness** (a small Node program, running as
   root) starts each job's Neovim as an **unprivileged user** in a fresh
   home and temp directory, with `nvim --embed --clean`, and builds the
   level with the same bootstrap the room child uses.
4. The harness feeds keys with `nvim_input`, pausing after `<Esc>` as
   `tests/player.lua` does. After each key it asks the child for its mode
   and, in Normal mode, snapshots the state over RPC and **evaluates the
   goal itself** with `goals.ts`, which the shared fixtures already keep in
   step with `goals.lua`. The child's own "solved" notification is
   ignored.
5. The first key index where the goal holds is the solve. `verified_keys` is
   the count of keys up to it, computed by the harness from the submitted
   log with `keys.split` rules, not reported by the child.
6. Each job has a wall-clock limit (10 s) enforced with SIGKILL, as the
   Setup sandbox already does, and all of that user's processes are killed
   and its files wiped before the next job.
7. The harness writes verdicts to its own stdout; the function validates
   them against a schema and updates runs, bests and the cache.

**Why the privilege split matters.** Replaying a key log is code execution:
`:!`, `:lua`, `:r !cmd`, `<C-r>=system(…)` and `:terminal` are all just
keys, and Ex commands are part of the legitimate game, so they can't be
filtered out. So everything the child touches is attacker-controlled. The
microVM (no network, no credentials, discarded afterwards) keeps that code
away from our data, and the uid split keeps it away from the harness that
decides the verdict.

**Why the harness isn't Neovim.** Neovim answers API requests on every RPC
channel it has. If the harness were a Neovim instance (as the game's parent
is), the replayed child could call `nvim_exec_lua` on it and run code as the
harness. The live room accepts that, since it's the player's own machine;
the verifier can't. So the harness is an RPC *client* that rejects every
request coming from the child. Making the buffer equal the goal with `:lua …` is
allowed: those keys are counted, and they cost far more than par.

**Version drift.** The arbiter is the latest stable Neovim in the snapshot.
If a replay fails and the client reported another supported minor version,
it's retried on that version. When a Neovim release changes behavior, bests
can be re-verified in bulk, because their logs are kept.

**Divergence from the live room.** The direct `--embed` path has no
terminal in between, so a few keys can behave differently from what the
player saw (Alt chords from a fast `<Esc>`, `<C-i>` vs `<Tab>`). Those runs
come out `mismatch` or `rejected` and keep their local result. Using the
full `player.lua` path (parent, terminal, child) in the verifier is an
option if this turns out to matter.

**Cost control.** Only runs that would improve the player's verified best
are verified; every other run is stored as T1 and expires after 90 days.
With the cache and per-user batches, Vercel Sandbox's Hobby allowance (5,000
sandbox creations and 5 CPU-hours a month) covers tens of thousands of
verifications (§8).

### 5.4 Time

Local time can't be trusted. The plugin and the browser both measure it, and
both can be edited. Server-issued tickets don't fix that: a ticket fetched
when the level opens only bounds the time from above, and a bot can solve a
known level in milliseconds anyway. What we do instead:

- **Rank by keys, break ties by server time** (§5.2). Time never decides a
  verified rank.
- **Consistency:** `deltas_ms` must have one entry per key and add up to
  `claimed.seconds` within 50 ms.
- **Human limits:** flag runs where a stretch of 10 or more keys averages
  under 40 ms per key, or where many gaps are identical to the millisecond.
  Flagged runs stay verified for keys, but their time is hidden and they
  don't appear in the speed view. Thresholds are a starting point to tune
  against real data.
- **Server window:** if the client fetched an attempt ticket
  (`POST /api/v1/attempts`), the claimed time can't exceed the time between
  ticket and submission. This only catches clumsy forgeries.

### 5.5 Optional: seeded "live" levels (T3)

For a daily speedrun, the server could generate the start state at attempt
time from a seed (for example, a `cursor_at` level whose target is placed
randomly), with par computed by the existing par finder (`scripts/par.lua`)
for that seed. A precomputed solution then doesn't exist, and a bot would
need a solver. The par finder *is* such a solver, so this raises the bar
rather than closing it. It needs level templates and per-seed par, which is
real engine work, so it's an experiment for later, not part of the core.

### 5.6 Per track and per source

| Source and track | Plan |
|---|---|
| Plugin, Motions and Usage, `config = "clean"` | T2. The main case, phase 1. |
| Plugin, `config = "mine"` | Unranked. The player's mappings change what keys mean. |
| Plugin, Setup track | Unranked until probes run **out of process**: today a config can override `vim.api.*` or write the probe report itself, which is fine locally but forgeable on a server. The fix is a probe harness that drives `nvim --embed -u init.lua` over RPC (answered by the C core, which a config can't patch) as the unprivileged user. |
| Web demo | The browser records `keydown` events as Vim notation (a shared fixture pins the mapping against `keys.ts`). The log is replayed **in Neovim**, so the web and the plugin share one board. Runs that only work in the emulation come out `rejected` with the reason "emulation-only", and the results card says so. |
| Custom `challenges_dir` | `unknown_level`. Community packs get boards once merged (§7). |

A loophole worth checking before phase 1: paste. `keys.lua` doesn't count
`<Paste>`, and the web counter ignores Cmd/Meta, so pasted text may reach
the room or the editor without being counted. A replay closes it for
ranked runs (pasted text isn't in the log, so the replay fails), but the
local game would still accept it.

### 5.7 What remains possible, said plainly

- Submitting an optimal solution someone else found, or one the par finder
  found. A replay proves the solution, not its author. We can show the
  any-motion optimum for `cursor_at` levels so the frontier is public
  knowledge, and keep key logs private (§6.6) so boards don't hand out
  answers.
- Botting time. That's why time doesn't rank.
- Multiple accounts. GitHub accounts are free. Mitigations: per-account rate
  limits, a minimum GitHub account age for public boards (`created_at` is
  public on the GitHub user endpoint; we store only the resulting boolean),
  and bans by GitHub id.
- Lying about the hint. The badge is shown, but it doesn't change rank.

## 6. Security and privacy

### 6.1 Assets and threat model

| Asset | Threat | Mitigation |
|---|---|---|
| Player accounts | Credential theft | We store no credentials. GitHub OAuth only; our tokens are stored as SHA-256 hashes; sessions expire (30 days, sliding) and can be revoked. |
| Plugin token on disk | Leak through dotfiles or a shared progress export | Kept in `stdpath("data")/vimdojo/auth.json` with mode `0600`, never in `progress.json`. A `vdj_` prefix makes leaks easy to spot. `VIMDOJO_TOKEN` env var for players who use a secret manager. `:VimDojo logout` revokes it server-side. |
| Plugin token in transit | Exposure in the process list | `curl` reads the header from stdin (`--config -`), never from argv; `--proto =https --tlsv1.2`. |
| Login flow | CSRF on the OAuth callback; code interception | `state` bound to a short-lived signed cookie, PKCE, exact redirect URI registered with GitHub. |
| Device flow | Phishing: an attacker gets a victim to enter the attacker's code | GitHub's page names the app; vimdojo tokens are low-value (they can submit runs and change a handle). The account page lists every login with its kind and date. |
| Leaderboard integrity | Forged runs | Replay verification (§5). |
| Verifier | A key log runs code | Firecracker microVM, network denied, no credentials, uid split, kill timeouts, per-user batches (§5.3). |
| Maintainer cloud accounts and bill | Takeover; a flood running up costs | Passkeys or 2FA on GitHub, Vercel and AWS; AWS root locked away; AWS Budgets alert at $1. Free plans pause instead of billing (Vercel Hobby), and provisioned DynamoDB throttles instead of billing (§8). |
| Players' machines | A community level runs code on every player | Human review for anything that executes (§7.3). |
| CI secrets (`LUX_API_KEY`) | A malicious PR exfiltrates them | Untrusted PR workflows use `pull_request` (never `pull_request_target`), read-only `GITHUB_TOKEN`, no secrets, first-time contributor approval required, actions pinned by SHA. |
| Personal data | Leaks, over-collection | §6.6. |

### 6.2 Identity

- **GitHub OAuth app with no scopes.** That grants read access to public
  profile data only. We keep the numeric id and discard the rest of the
  response, including any public email. Players are developers who almost
  all have GitHub; the plugin itself is distributed there.
- **Browser:** authorization-code flow with PKCE.
- **Plugin:** GitHub's device flow, proxied by our API, so the plugin only
  ever holds a vimdojo token. `:VimDojo login` prints a code and opens
  `github.com/login/device`.
- **Not chosen:** magic links (they need email addresses and an email
  sender: more PII and another vendor); passwords (we'd store credentials);
  passkeys (good for the browser, but the plugin can't do WebAuthn; they
  could be added later as a second login method for the web only). Other
  OAuth providers (GitLab, Codeberg) can be added the same way if asked
  for.

### 6.3 Handles

- 3 to 20 characters, `[a-z0-9_-]`, unique case-insensitively, with a
  reserved list (`admin`, `vimdojo`, `neovim`, …) and a small blocklist.
- The default is **not** the GitHub login. Players pick one at first login,
  so the board doesn't link to their GitHub identity unless they choose
  that. An optional "show my GitHub profile" toggle can come later.
- One change every 30 days; old handles are held for 90 days to prevent
  impersonation.

### 6.4 Encryption and secrets

- **In transit:** HTTPS only (Vercel terminates TLS), HSTS, and TLS from
  functions to DynamoDB through the AWS SDK.
- **At rest:** DynamoDB encrypts every table by default. Tokens are stored
  only as hashes. Key logs are compressed, not encrypted: they're game
  input, not personal data.
- **Secrets:** the GitHub client secret and the ticket/session signing key
  live in Vercel environment variables marked sensitive. DynamoDB access
  uses Vercel's OIDC federation to an IAM role allowed only
  `GetItem/PutItem/UpdateItem/DeleteItem/Query/TransactWriteItems` on the
  one table and its indexes; no AWS access keys exist anywhere. Nothing
  secret is ever in the repo; secret scanning with push protection is on
  (free for public repos).
- **Rotation:** the signing key supports two active versions so it can be
  rotated without logging everyone out.

### 6.5 Web hardening

- **Same origin** for site and API, so no CORS headers at all.
- **Session cookie** `__Host-vdj_session`: `HttpOnly`, `Secure`,
  `SameSite=Lax`, `Path=/`, opaque random 256-bit value.
- **CSRF:** every state-changing request needs a JSON body
  (`Content-Type: application/json`, which a cross-site form can't send
  without a preflight), a matching `Origin` header, and `SameSite=Lax`.
  Bearer-token requests aren't cookie-based, so CSRF doesn't apply to them.
- **CSP:** `default-src 'self'`, no third-party scripts (already the case),
  `frame-ancestors 'none'`. Handles are rendered as text, never as HTML.
- Tokens are never accepted in query strings.

### 6.6 Data, retention and deletion

| Data | Why | Kept |
|---|---|---|
| GitHub numeric id | To recognize a returning login | Until account deletion |
| Handle | Shown on boards | Until deletion (then held 90 days, unlinked) |
| Runs: key log, claimed keys/time, client and Neovim version | Verification and boards | 90 days, except the runs behind current bests |
| Bests | Boards | Until deletion |
| Token hashes | Login | Until expiry or revocation |
| IP address | Rate limiting unauthenticated routes | Only as a salted hash in a counter with a 24 h TTL; the salt rotates daily |

Not collected: email, real name, avatar, OS, user agent, analytics, cookies
other than the session cookie (strictly necessary, so no consent banner).

- **Key logs are private** to their owner. Boards show counts, not
  solutions. Whether to reveal solutions later (after a season, or to
  players who've matched that count) is an open decision (§11).
- **Deletion** (`DELETE /api/v1/me`) removes the user's partition, the
  handle claim, the GitHub link and every token at once; board entries go
  with the bests. If point-in-time recovery is enabled, data ages out of
  backups within its 35-day window; the privacy page says so.
- **Export** (`GET /api/v1/me/export`) returns everything above as JSON.
- A short **privacy page** lists what's stored, why, for how long, and the
  processors (Vercel, AWS, GitHub). This covers the GDPR basics (access,
  erasure, minimization) for a hobby service. Choose an EU region for both
  Vercel functions and DynamoDB if most players or the maintainer are in
  the EU.

### 6.7 Abuse and rate limits

- `POST /runs`: 30 per minute and 1,000 per day per user; payload ≤ 16 KB.
- Login routes: 10 per minute per IP hash.
- Board reads are CDN-cached, so they rarely reach a function.
- The verifier only runs for personal-best candidates and stops taking new
  batches when the month's Sandbox allowance is 80% used (runs stay
  pending, and the UI says verification is delayed).
- Maintainer tools: reject a run, ban a GitHub id, release a handle. A
  "report" link opens a GitHub issue from a template.

### 6.8 Plugin: offline stays the default

```lua
require("vimdojo").setup({
  online = {
    enabled = false,   -- nothing touches the network until this is true
    submit = "ask",    -- "ask" | "auto" | "never", once logged in
    url = "https://vimdojo.vercel.app",
  },
})
```

- No network at startup, ever. Online commands (`:VimDojo login`,
  `logout`, `board`, `submit`) only exist to be called.
- Calls are async (`vim.system` + `curl`), so the game never waits on the
  network. A failed submission goes to an outbox in `stdpath("state")` and
  is retried on the next online action.
- `curl` is the only external tool, and only for online features. It ships
  with macOS, Windows 10+ and nearly every Linux distribution. The plugin
  stays dependency-free.
- No telemetry. The plugin sends a run only when the player submits it.

## 7. Community and challenges

### 7.1 How levels arrive

| Option | Pros | Cons |
|---|---|---|
| **A. Pull requests (recommended)** | Already works (CONTRIBUTING, authoring guide). CI proves every level in real rooms. Review, history and attribution come free. No backend, no write tokens. | Requires git and GitHub. |
| B. In-app submission → bot opens the PR | Friendlier for non-git users. | A GitHub App with write access, a moderation queue and a new attack surface, for what is still a PR in the end. |
| C. External pack registry | Authors keep packs in their own repos. | Code-executing levels from unreviewed repos on players' machines; hash pinning, trust prompts and a registry to run. |

A low-cost middle ground for B, later: a level editor in the web demo that
exports JSON and opens GitHub's "new file" page prefilled with it. GitHub
does the authentication and the PR; we run nothing.

### 7.2 Automated gates (CI)

Already in place, and they apply to community levels unchanged:

- JSON Schema validation (`make validate`).
- Solution tests in real clean rooms: the start doesn't satisfy the goal,
  the reference solution does, within `par_keys` (Neovim 0.10, stable,
  nightly, and Windows).
- The emulation gate in Chromium for any `web_demo` flag.
- The par finder for `cursor_at` levels.

To add:

- **Par report as a PR comment:** taught-motion and any-motion optimum, so
  reviewers see a dishonest or loose par at a glance.
- **Content checks:** id uniqueness across packs, lengths (lines, files,
  probes), no absolute paths (already enforced for `files`).
- **Code-executing fields flagged:** a PR touching `preset.commands`, `lua`
  probes, or a Setup starter snippet gets a `needs-code-review` label and a
  required CODEOWNERS review. These run on every player's machine (a Setup
  starter runs as soon as the level opens), so they get human review, not
  just green CI.
- **CI hardening** for untrusted PRs (§6.1): the PR's own tests run its own
  levels, which is code execution in CI by design.

### 7.3 Human review and the community area

- **Curated packs** stay in `challenges/` with the current par rule (taught
  motions only) and the main progression.
- **Community packs** go in `community/`, as a fourth "Community" track
  with its own menu section. Their par rule is the one the Setup track uses:
  the best known solution with any keys. They don't block progression.
- **Rules for community levels:** no `lua` probes and no `preset.commands`
  beyond an allowlist (`vsplit`, `split`, `vimgrep`, `cfirst`, `cd` inside
  the workspace, `lua vim.diagnostic.set(...)`). Anything else needs a
  maintainer and goes to curated packs.
- **Promotion:** popular, well-rated community levels can be moved into a
  curated pack (keeping their id and author credit).
- A **level review checklist** in the PR template: one idea, unambiguous
  goal, original text, honest par, no code beyond the allowlist.

### 7.4 Licensing and attribution

- Everything in the repo is MIT. Contributions are licensed the same way
  (GitHub's terms make inbound = outbound the default); CONTRIBUTING says so
  explicitly and the PR template has a checkbox.
- Level text must be original or MIT-compatible. No copied song lyrics,
  book excerpts or code from GPL projects.
- A new optional `authors` field (GitHub handles) on packs and levels. A
  credits section on the site is rendered at build time from it, like the
  curriculum.

### 7.5 Ratings, reports and moderation

- After a **verified** solve, the results card offers 👍/👎 and a
  difficulty vote (easy, right, hard). Only verified solvers can vote, which
  limits sybil votes. Stored per `(user, level)`, aggregated per level, used
  to sort the Community track and pick promotions.
- "Report this level" and "report this handle" open GitHub issue templates.
- A Code of Conduct (Contributor Covenant) for the repo and Discussions.

### 7.6 Daily challenge, sharing and discussion

- **Daily challenge:** a curated rotation in `challenges/daily.json` (or a
  hash of the date over eligible levels). Works offline: the plugin and the
  site pick the same level from the date. Online, it gets its own board,
  reset every day (UTC).
- **Shareable results** as spoiler-free text, Wordle-style, copyable from
  the results card in both clients:
  `vimdojo daily 2026-10-19 ★★★ 7 keys (par 7) 4.2s`. Later, a share URL
  with an Open Graph card.
- **Discussions:** GitHub Discussions (free, already authenticated, with
  moderation tools) rather than our own forum. A "Discuss" link per level
  opens its thread. Spoiler etiquette: solutions in spoiler blocks, daily
  solutions only after the day ends.
- Later ideas: weekly seasons, "beat my keys" challenge links, per-pack
  boards.

## 8. Platform evaluation and cost

### 8.1 Free-tier fit (as of 2026-10-19)

**Vercel Hobby** (free; non-commercial use only, donations allowed): 1M
function invocations, 4 h active CPU and 360 GB-h memory a month, 100 GB
data transfer, 300 s max function duration, 1 h runtime log retention.
Exceeding a limit pauses the project; it never bills. **Vercel Sandbox** on
Hobby: 5,000 sandbox creations, 5 h active CPU and 420 GB-h memory a month,
10 concurrent, 45 min sessions, firewall network policies; paused when
exceeded. Watch out: Hobby can't deploy from repos owned by a GitHub
organization, so this works while the repo stays under a personal account.
Pro is $20 per seat per month, including $20 of usage credit.

**DynamoDB** (always free): 25 GB storage on the Standard table class, plus
25 provisioned RCU and 25 WCU shared by all tables and indexes in a region.
On-demand mode gets the storage but not the request allowance: $0.625 per
million writes and $0.125 per million reads (us-east-1). AWS needs a card on
file, so **provisioned mode within the free capacity is the safe default**:
too much traffic throttles instead of billing. A split like table 10/10,
board index 10/10, pending index 5/5 fits. Switch to on-demand with a
maximum-throughput cap if throttling shows up.

### 8.2 Estimates

Assumptions: a verification costs about 0.3 s of CPU; batches average 10
runs, each in a 1-vCPU, 2 GB sandbox billed for its 1-minute minimum; a run
item is about 1.5 KB; board reads are mostly CDN hits.

| | Small | Medium |
|---|---|---|
| Monthly active players | 500 | 20,000 |
| Runs submitted / month | 20,000 | 1,000,000 |
| Runs verified (PB candidates, after cache) | 5,000 | 150,000 |
| Function invocations | ~60k | ~1.5M |
| Sandbox | ~500 creations, ~0.5 CPU-h | ~15,000 creations, ~13 CPU-h |
| DynamoDB writes | ~0.01 writes/s average | ~1 write/s average, peaks of ~20 |
| DynamoDB storage | < 100 MB | ~1.5 GB (90-day TTL on runs) |
| **Vercel** | $0 (Hobby) | $20 Pro. Usage (Sandbox ~$11 memory + ~$2 CPU, functions ~$1) fits in the included $20 credit |
| **DynamoDB** | $0 | $0 provisioned if peaks fit in 25 WCU; otherwise ~$3 on-demand |
| **Total** | **$0** | **~$20–25 / month** |

Optional at any scale: a custom domain (~$10–15 a year), and DynamoDB
point-in-time recovery (about $0.20 per GB-month, so cents).

### 8.3 Alternatives

| Stack | Strengths | Weaknesses for vimdojo |
|---|---|---|
| **Vercel + DynamoDB + Vercel Sandbox (recommended)** | MicroVM sandboxes for the Neovim replay on the same platform, free on Hobby; Node runtime shares the web's TypeScript; hard caps on the free plan; AWS durability; no static keys via OIDC. | Two vendors and two dashboards; AWS needs a card; ranks need denormalized keys instead of SQL. |
| Cloudflare Workers + D1 | One vendor, no card for the free plan, SQL is natural for boards (`ORDER BY keys, first_at`), built-in rate limiting and Turnstile. Free: 100k requests a day, 10 ms CPU per request; D1 5M rows read and 100k written a day (hard-enforced since 2026-09-01); $5/month paid plan. | No free way to run Neovim: the verifier needs Cloudflare Containers (paid plan) or an outside runner. The Workers runtime isn't Node. |
| Supabase | Postgres, row-level security, GitHub OAuth built in. | Free projects pause after a week without activity, which a sporadic hobby leaderboard will hit; 500 MB database; the verifier still needs separate compute. |

If the verifier ever moves off Vercel Sandbox (cost, limits), Cloudflare
Workers + D1 becomes the better API host. The `web/server/` storage interface
keeps that move to one adapter.

## 9. Changes to existing code (when built)

None now. For orientation:

- **Plugin:** record the counted keys and gaps alongside the count
  (`keys.capture` already sees them); an `online.lua` module (login,
  submit, outbox) behind the `online` option; results-card actions for
  submit and share; the content hash (`vim.fn.sha256` over a small
  canonical JSON encoder).
- **Level hash:** SHA-256 of canonical JSON (sorted keys) over the fields
  that define play: `start_text` or `files` + `open`, `cursor_start`,
  `goal`, `options`, `preset`, `requires`. Not `par_*`, `hint`, `title`,
  `description`, `teaches` or `web_demo`: changing them doesn't change the
  solution space, so boards survive copy edits and par tweaks. A shared
  fixture pins the hash in Lua and TS.
- **Web:** a key-notation recorder next to the counter, a board view, a
  login button, share text.
- **Schema:** optional `authors`; `daily.json`.
- **New:** `web/api/`, `web/server/`, `verifier/`, the manifest build step,
  deploy workflow, privacy page.
- **Setup probes:** an out-of-process runner, before Setup levels can be
  ranked.

## 10. Roadmap

Each phase is useful on its own and can stop there.

| Phase | Scope | Cost | Done when |
|---|---|---|---|
| **0. No backend** (smallest useful step) | Daily challenge picked from the date, offline, in both clients. Share text on the results card. GitHub Discussions with level and daily categories. `authors` field and credits section. PR template, licensing statement, CI hardening for untrusted PRs. Check the paste loophole (§5.6). Record key logs locally. | $0 | Players can play and share the same daily level, and community PRs have a clear path. |
| **1. Verified boards, plugin** | Vercel project (site moves there, same origin); DynamoDB table; GitHub device + web login; `POST /runs`; verifier in Vercel Sandbox for Motions and Usage; per-level boards on the site (read-only); profile, export, delete; rate limits; privacy page. | $0 | A plugin player logs in, solves a level, and sees a verified rank on the site within a minute. |
| **2. Web runs and daily boards** | Browser key-notation recorder; web submissions replayed in Neovim; daily boards; global totals; plausibility flags on time. | $0 small | Web and plugin share one board; the daily has a board. |
| **3. Community** | `community/` track, allowlist for presets, par-report PR comments, ratings after verified solves, report templates, promotions. Optional: out-of-process probes and ranked Setup levels. | $0 | A community pack merges, appears in both clients, and has its own boards and ratings. |
| **4. Experiments** | Seeded live dailies (T3), seasons, web level editor with GitHub prefill, solution reveal after a season, a pack registry. | varies | Each one decided separately. |

## 11. Open decisions

| # | Decision | Options | Recommendation |
|---|---|---|---|
| L1 | Stack | Vercel + DynamoDB; Cloudflare Workers + D1; Supabase | **Vercel Hobby + DynamoDB (provisioned, free capacity) + Vercel Sandbox.** The sandbox is what makes free server-side replay possible. |
| L2 | Ranking | Points; keys then self-reported time; keys then server first-achieved time | **Keys, then first-achieved.** Points tie at 1000, and time can't be verified. Self-reported time gets a labelled speed view. |
| L3 | Unverified runs | Public "unverified" board; private only | **Private only.** Public boards show T2 only. |
| L4 | Arbiter for web runs | Neovim; the TS emulation in headless Chromium | **Neovim.** One board, one standard ("real Vim"), and a smaller verifier image. |
| L5 | Setup track | Unranked; ranked after out-of-process probes | **Unranked for now**, ranked once probes can't be forged (phase 3). |
| L6 | Site hosting | Move to Vercel (same origin); keep GitHub Pages + cross-origin API | **Move to Vercel.** First-party cookies, no CORS. Pages redirects. |
| L7 | Login | GitHub only; plus GitLab/Codeberg; passkeys; magic links | **GitHub only** to start; other OAuth providers on request; no email-based login. |
| L8 | Community intake | PRs; in-app submission; external registry | **PRs into `community/`**, with the web-editor prefill trick later. |
| L9 | Solution visibility | Never; after a season; to players who've matched the count | **Private** in phase 1; revisit with real players. |
| L10 | Region | US (`iad1` + `us-east-1`); EU (`dub1` + `eu-west-1`) | **Co-locate functions, Sandbox and DynamoDB**; EU if most players or the maintainer are in the EU. |
| L11 | Domain | `vimdojo.vercel.app`; own domain | Start on `vercel.app`; an own domain (~$12/year) is the only cost worth paying early, because changing the OAuth callback and share links later is a chore. |
| L12 | Retention | Run TTL, handle hold | 90 days for non-best runs, 90-day handle hold, 30-day sliding sessions. |

## 12. Risks

- **Verifier fidelity.** Replays use `--embed`, not the terminal path, so a
  few keys may behave differently (§5.3). Measure on the existing solution
  tests first: every reference solution must verify.
- **Free-tier changes.** Vercel and AWS have changed free tiers before. The
  storage adapter and the sandbox-only verifier keep a move contained, and
  the plugin works offline whatever happens.
- **Maintenance load.** Moderation, bans and appeals are human work. Keeping
  boards verified-only and discussions on GitHub keeps that small.
- **Commercial use.** Vercel Hobby is non-commercial. Sponsorships through
  donations are fine; ads or paid features would mean Pro.
- **Spoilers.** Boards make the optimum visible as a number, which some
  players find demotivating. Per-level boards are opt-in from the results
  card, not shown before a solve.

## Sources

Checked 2026-10-19.

- Vercel limits: <https://vercel.com/docs/limits>
- Vercel fair use guidelines (Hobby allotments, commercial use):
  <https://vercel.com/docs/limits/fair-use-guidelines>
- Vercel Sandbox pricing and quotas: <https://vercel.com/docs/sandbox/pricing>
- Vercel Sandbox concepts (Firecracker, firewall):
  <https://vercel.com/docs/sandbox/concepts>
- DynamoDB on-demand pricing and free tier:
  <https://aws.amazon.com/dynamodb/pricing/on-demand/>
- Cloudflare Workers pricing (Workers, KV, D1):
  <https://developers.cloudflare.com/workers/platform/pricing/>
- D1 free-tier enforcement:
  <https://developers.cloudflare.com/changelog/post/2026-09-01-d1-free-tier-limit-enforcement/>
- Supabase free-plan pausing (third-party summary, not verified against
  Supabase's own page): <https://www.jetadmin.io/blog/supabase-pricing-2026-guide-to-plans-limits-and-real-world-costs/>
