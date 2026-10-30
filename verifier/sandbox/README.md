# Running the verifier in Vercel Sandbox

The verifier replays key logs in a Vercel Sandbox microVM in Frankfurt
(`fra1`), resumed from a snapshot that holds a pinned Neovim, vimdojo's Lua
and the bundled harness, with the network denied.

## One-time setup (Vercel Hobby, free)

1. Sign in at https://vercel.com (Hobby plan).
2. Create an empty project for the verifier, for example
   `npx vercel login`, then `npx vercel project add vimdojo-verifier`.
3. Note the **team id** (Team Settings → General → Team ID, `team_…`) and
   the **project id** (the project's Settings → General → Project ID,
   `prj_…`).
4. Create an **access token** (Account Settings → Tokens), scoped to that
   team, with an expiry.
5. Put `VERCEL_TOKEN`, `VERCEL_TEAM_ID` and `VERCEL_PROJECT_ID` in
   `verifier/.env` (gitignored). Never commit it or paste the token anywhere else.

## Build the snapshot

```sh
cd verifier
npm run build && npm run build:sandbox
set -a; . ./.env; set +a
node dist/build-snapshot.js     # prints VERIFIER_SNAPSHOT_ID=snap_…
```

Add `VERIFIER_SNAPSHOT_ID` to `verifier/.env`. Rebuild the snapshot whenever
the room's Lua, the goal rules or the harness change.

## Run a batch

Every Motions and Usage reference solution:

```sh
node dist/run-batch.js
```
