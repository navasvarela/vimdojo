# vimdojo v3 plan: verified leaderboards

> Follows [PLAN-v2.md](PLAN-v2.md) (three tracks, shipped as v0.4.0) and the
> community phase 0 (daily challenge, share text, credits, shipped as
> v0.5.0). The design is in
> [docs/proposals/leaderboard-and-community.md](docs/proposals/leaderboard-and-community.md);
> this plan turns its phase 1 into milestones on the stack chosen below. Same
> working agreements as before: milestone by milestone, tests first-class,
> decisions logged in `docs/decisions.md`, ask before deviating on
> architecture.

## 1. Goal

A plugin player can opt in, log in with GitHub, solve a level, and see a
**verified** rank on vimdojo.org within a minute. The server replays the key
log in a clean Neovim and recounts the keys, so boards only show results it
can reproduce.

Nothing changes for players who don't opt in: the plugin and the demo still
work offline, with no account and no network calls.

### Non-goals for v3

- Web-demo submissions and daily boards (proposal phase 2).
- The `community/` track, ratings and moderation tools (phase 3).
- Ranking the Setup track: its probes run in the same Lua state as the
  player's config, so a config could forge them (L5).
- Anything that costs money at small scale.

## 2. Decisions (agreed 2026-10-30)

These settle the proposal's open decisions (its §11).

| # | Decision | Chosen |
|---|---|---|
| L1 | Stack | **Cloudflare Workers + D1** for the API and storage, at `api.vimdojo.org`, in the Cloudflare account that already holds the DNS and analytics (no card needed). **Vercel Sandbox** (Hobby) runs the replays, called from a scheduled Worker with an access token. |
| L2 | Ranking | Fewest **verified keys**, ties broken by the server's first-achieved time. Self-reported time is shown with a label and never ranks. |
| L3 | Unverified runs | Private only. Public boards show verified runs only. |
| L4 | Arbiter for web runs | Neovim (relevant from phase 2). |
| L5 | Setup track | Unranked until probes run out of process. |
| L6 | Site hosting | Stays on **GitHub Pages** at vimdojo.org. The API on `api.vimdojo.org` is same-site, so a `SameSite=Lax` session cookie works without moving the site. *(Changed from the proposal, which moved the site to Vercel.)* |
| L7 | Login | GitHub only: device flow for the plugin, authorization code + PKCE for the browser. |
| L8 | Community intake | Pull requests (phase 3). |
| L9 | Solution visibility | Key logs are private. |
| L10 | Region | **EU.** The D1 database is created with `jurisdiction: "eu"`, which pins storage and execution to the EU (it can't be added later). |
| L11 | Domain | `api.vimdojo.org`. *(Settled: vimdojo.org is live.)* |
| L12 | Retention | Non-best runs expire after 90 days, released handles are held for 90 days, sessions slide over 30 days. |

## 3. What we checked before planning (2026-10-30)

| Question | Result | Consequence |
|---|---|---|
| Can Vercel Sandbox be used from outside Vercel? | Yes: the SDK takes an access token, a team id and a project id instead of a Vercel OIDC token. | A Cloudflare Worker can drive it. The token is a Worker secret. |
| Can D1 guarantee EU residency? | Yes, with `jurisdiction: "eu"` at creation. A location hint (`weur`) is only a preference. | Create the database with the jurisdiction. |
| Do Workers' free limits fit the orchestrator? | 10 ms CPU per invocation (time spent waiting on `fetch` and D1 doesn't count), 50 external subrequests per invocation, cron down to 1 minute, 5 cron triggers per account, 100,000 requests a day. | One cron run verifies a batch with a handful of Sandbox calls. Verdict parsing must stay small. |
| Where does Vercel Sandbox run? | In the region you ask for; `fra1` (Frankfurt) is one. | The verifier runs in the EU too. Jobs still carry only the level JSON and the key log: no user id, handle or token. |
| Does the Sandbox SDK run on Workers? (M15) | Yes, deployed on the free plan with `nodejs_compat`. 30 batches used 8-81 ms of CPU against the documented 10 ms, and all finished `ok`. | Keep the SDK, but treat a killed run as normal: pending runs stay pending and are retried. See the risk below. |

## 4. Architecture

```
 Neovim plugin ──(curl, opt-in)──► api.vimdojo.org  (Cloudflare Worker)
 vimdojo.org (GitHub Pages) ─────► │  auth · runs · boards · profiles
   reads boards, logs in           │
                                   ├── D1, jurisdiction "eu"
                                   │     users, tokens, runs, bests, verdicts
                                   │
                    cron, every minute
                                   ▼
                  Vercel Sandbox microVM (network denied, no credentials)
                    harness (Node RPC client) ──► nvim --embed --clean
                    as an unprivileged user, one job at a time
```

- **The Worker** validates input with the zod schemas the web already uses,
  authenticates, rate-limits, and reads and writes D1. It never runs Neovim.
- **The verifier** follows the proposal's §5.3: per-user batches, a verdict
  cache keyed by `(level_hash, nvim, log_hash)`, a Node harness that is an
  RPC *client* (never a Neovim) feeding keys with `nvim_input` and
  evaluating the goal itself with `goals.ts`, a 10 s wall-clock limit per
  job, and an uid split between the harness and the replayed Neovim.
- **The level manifest** is generated at build time from `challenges/`
  (like the curriculum) and maps each level id to its content hash and its
  ranked status. The Worker and the Sandbox snapshot are built from the same
  commit.
- **Shared code:** `keys.ts`, `goals.ts`, `scoring.ts` and the zod level
  parser move into a package both the web and the Worker import, so there's
  still one TypeScript port of the rules.

Suggested layout: `api/` (the Worker, its D1 migrations and `wrangler.toml`),
`verifier/` (the harness and the snapshot build script), and the shared
rules under `web/src/` imported by both.

## 5. Milestones

| Milestone | Scope | Done when |
|---|---|---|
| **M15 Verifier spike** | Node harness replaying key logs in `nvim --embed --clean` with the goal checked by `goals.ts`; run it locally over every Motions and Usage reference solution; then inside a Vercel Sandbox snapshot, started from a Worker. Measure time and Sandbox usage per batch. | Every Motions and Usage reference solution verifies with its exact key count, locally and in the Sandbox, triggered from a Worker. Any key that diverges from the live room is listed in `docs/decisions.md`. |
| **M16 Level identity and key logs** | Level content hash (canonical JSON over the fields that define play) in Lua and TS with a shared fixture; manifest build step; the plugin records each attempt's counted keys and gaps to a private log in `stdpath("state")`, never in `progress.json`. | Lua and TS agree on every level's hash; a solved level leaves a key log that the M15 harness verifies. |
| **M17 API and accounts** | Worker at `api.vimdojo.org`; D1 schema and migrations (EU jurisdiction); GitHub device flow (plugin) and code + PKCE (site); handles; hashed tokens; rate limits; account export and delete; privacy page. | `:VimDojo login` signs in through GitHub and picks a handle; the site can sign in, show the account, export it and delete it. |
| **M18 Submit and verify** | `POST /runs` (idempotent, size-capped), the plugin's opt-in `online` config with `submit = "ask"` and an outbox for failed sends, the cron verifier with the verdict cache, bests, and the `verified` / `mismatch` / `rejected` / `unranked` statuses. | A submitted best is verified within a minute; a forged key count comes back `mismatch` with the true count; a log that doesn't solve the level comes back `rejected`. |
| **M19 Boards on the site** | Per-level boards (top 50, verified only, CDN-cached), the player's own rank, public profiles, a link from the results card. **Release v0.6.0.** | The phase 1 goal in §1 holds end to end on production. |

M16 (plugin and shared code) and M17 (Worker and D1) don't touch the same
files, so they can run in parallel once M15 proves the verifier.

## 6. Risks

- **The free plan's CPU limit.** Verification batches went over the
  documented 10 ms without being stopped (M15), but that isn't a guarantee.
  M18 watches for `exceededCpu`. Fallbacks: call the Sandbox REST API with
  `fetch` from a smaller bundle, or the $5 Workers plan.
- **Verifier fidelity.** The `--embed` path has no terminal in between, so a
  few keys (Alt chords, `<C-i>` vs `<Tab>`) may differ from the live room.
  All 66 reference solutions match (M15), but real players' logs may find
  cases they don't; those runs come out `mismatch` or `rejected` and keep
  their local result.
- **Free-tier limits and changes.** Workers' 10 ms CPU, Sandbox's Hobby
  allowance, D1's daily caps. Only runs that would improve a player's best
  are verified, identical logs hit the cache, and every limit pauses rather
  than bills. The plugin keeps working offline whatever happens.
- **Two vendors.** Cloudflare for data, Vercel for compute. The Sandbox job
  interface (level JSON + key log in, verdict out) is small enough to move
  to another runner if needed.
- **Vercel Hobby is non-commercial.** Fine for a free, open-source game;
  ads or paid features would need Vercel Pro.
- **Moderation.** Bans, handle disputes and appeals are human work.
  Verified-only boards and GitHub-only login keep it small.
