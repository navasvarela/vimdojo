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
migrations command when `migrations/` changed. `.secrets` can be deleted after
the first deploy.
