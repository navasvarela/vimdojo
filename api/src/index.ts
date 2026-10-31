import { type App, handleRequest, sweep } from "./app"
import type { Env } from "./config"
import { realGitHub } from "./github"
import { Store } from "./store"

function appFor(env: Env): App {
  return {
    store: new Store(env.DB),
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

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, appFor(env))
  },
  scheduled(_event: ScheduledController, env: Env, context: ExecutionContext): void {
    context.waitUntil(sweep(appFor(env)))
  },
} satisfies ExportedHandler<Env>
