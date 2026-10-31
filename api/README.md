# The vimdojo API

A Cloudflare Worker at `api.vimdojo.org`, with its data in D1 (pinned to the EU).
See [PLAN-v3.md](../PLAN-v3.md) and `docs/decisions.md`.

```sh
npm test           # the whole app on a real local D1 (wrangler's own)
npm run typecheck
npm run dev        # wrangler dev; copy .dev.vars.example to .dev.vars first
```

## Deploying

Needs `npx wrangler login`. The D1 database already exists (`wrangler.toml`).

One-time setup: a GitHub OAuth app (Settings → Developer settings → OAuth Apps)
with

- Homepage URL: `https://vimdojo.org`
- Authorization callback URL: `https://api.vimdojo.org/api/v1/auth/github/callback`
- **Enable Device Flow** ticked

Its client id goes in `wrangler.toml` as `GITHUB_CLIENT_ID` (it isn't secret).
Put the secrets in `api/.secrets` (gitignored):

```sh
GITHUB_CLIENT_SECRET=...
RATE_LIMIT_SALT=...   # any long random string, for example: openssl rand -hex 32
```

Then, from `api/`:

```sh
npx wrangler d1 migrations apply vimdojo --remote
npx wrangler deploy --secrets-file .secrets
```

Later deploys need only `npx wrangler deploy` (the secrets stay), plus the
migrations command, **first**, when `migrations/` changed. `.secrets` can be deleted
after the first deploy.

## The verifier

A cron trigger replays pending runs every minute in a Vercel Sandbox
(`verifier/sandbox/README.md`). It needs four more secrets: `VERCEL_TOKEN`,
`VERCEL_TEAM_ID`, `VERCEL_PROJECT_ID` and `VERIFIER_SNAPSHOT_ID`.

- **Rebuild the snapshot when levels, the room's Lua or the harness change,** then
  update `VERIFIER_SNAPSHOT_ID`. Until then, runs on a changed level end as `failed`,
  because the snapshot doesn't have that version of the level.
- **When the Vercel token expires,** verification stops and runs stay pending, at no
  cost to them. Replace it with `wrangler secret put VERCEL_TOKEN`.
- Batches stop at 4,000 a month (`verify.ts`), and runs resume the next month.
