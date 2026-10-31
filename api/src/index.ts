import { type App, handleRequest, isPublicPath, sweep } from "./app"
import type { Env } from "./config"
import { realGitHub } from "./github"
import { RunStore } from "./run-store"
import { sandboxRunner } from "./sandbox"
import { Store } from "./store"
import { verifyOnSubmit, verifyPending } from "./verify"

const SWEEP_CRON = "17 3 * * *"

function runnerFor(env: Env) {
  return sandboxRunner({
    token: env.VERCEL_TOKEN,
    teamId: env.VERCEL_TEAM_ID,
    projectId: env.VERCEL_PROJECT_ID,
    snapshotId: env.VERIFIER_SNAPSHOT_ID,
  })
}

function appFor(env: Env, background: (work: Promise<void>) => void): App {
  const store = new Store(env.DB)
  const runs = new RunStore(env.DB)
  return {
    store,
    runs,
    github: realGitHub({ clientId: env.GITHUB_CLIENT_ID, clientSecret: env.GITHUB_CLIENT_SECRET }),
    config: {
      siteOrigin: env.SITE_ORIGIN,
      apiOrigin: env.API_ORIGIN,
      clientId: env.GITHUB_CLIENT_ID,
      rateLimitSalt: env.RATE_LIMIT_SALT,
    },
    now: Date.now,
    verifySoon: (userId) => {
      background(
        verifyOnSubmit(runs, runnerFor(env), userId, Date.now(), (subject, window) =>
          store.countRequest(subject, window),
        ),
      )
    },
  }
}

function verify(env: Env): Promise<void> {
  return verifyPending(new RunStore(env.DB), runnerFor(env), Date.now())
}

/** A busy board costs one database read a minute, whoever is looking at it. */
async function respond(request: Request, env: Env, context: ExecutionContext): Promise<Response> {
  const background = (work: Promise<void>): void => context.waitUntil(work)
  const cacheable = request.method === "GET" && isPublicPath(new URL(request.url).pathname)
  if (!cacheable) {
    return handleRequest(request, appFor(env, background))
  }
  const key = new Request(request.url)
  const cached = await caches.default.match(key)
  if (cached !== undefined) {
    return cached
  }
  const response = await handleRequest(request, appFor(env, background))
  if (response.ok) {
    context.waitUntil(caches.default.put(key, response.clone()))
  }
  return response
}

export default {
  fetch(request: Request, env: Env, context: ExecutionContext): Promise<Response> {
    return respond(request, env, context)
  },
  scheduled(event: ScheduledController, env: Env, context: ExecutionContext): void {
    context.waitUntil(
      event.cron === SWEEP_CRON
        ? sweep(appFor(env, (work) => context.waitUntil(work)))
        : verify(env),
    )
  },
} satisfies ExportedHandler<Env>
