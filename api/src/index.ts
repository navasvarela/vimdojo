import { type App, handleRequest, sweep } from "./app"
import type { Env } from "./config"
import { realGitHub } from "./github"
import { RunStore } from "./run-store"
import { sandboxRunner } from "./sandbox"
import { Store } from "./store"
import { verifyPending } from "./verify"

const SWEEP_CRON = "17 3 * * *"

function appFor(env: Env): App {
  return {
    store: new Store(env.DB),
    runs: new RunStore(env.DB),
    github: realGitHub({ clientId: env.GITHUB_CLIENT_ID, clientSecret: env.GITHUB_CLIENT_SECRET }),
    config: {
      siteOrigin: env.SITE_ORIGIN,
      apiOrigin: env.API_ORIGIN,
      clientId: env.GITHUB_CLIENT_ID,
      rateLimitSalt: env.RATE_LIMIT_SALT,
    },
    now: Date.now,
  }
}

function verify(env: Env): Promise<void> {
  const runner = sandboxRunner({
    token: env.VERCEL_TOKEN,
    teamId: env.VERCEL_TEAM_ID,
    projectId: env.VERCEL_PROJECT_ID,
    snapshotId: env.VERIFIER_SNAPSHOT_ID,
  })
  return verifyPending(new RunStore(env.DB), runner, Date.now())
}

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, appFor(env))
  },
  scheduled(event: ScheduledController, env: Env, context: ExecutionContext): void {
    context.waitUntil(event.cron === SWEEP_CRON ? sweep(appFor(env)) : verify(env))
  },
} satisfies ExportedHandler<Env>
