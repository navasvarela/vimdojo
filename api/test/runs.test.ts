// Submitting and verifying runs, on a real local D1 with a stand-in for the sandbox.
import { readdirSync, readFileSync } from "node:fs"
import { join } from "node:path"
import { afterEach, beforeEach, describe, expect, it } from "vitest"
import { getPlatformProxy } from "wrangler"
import { type App, handleRequest, sweep } from "../src/app"
import type { Env } from "../src/config"
import { sha256Hex } from "../src/crypto"
import type { GitHub } from "../src/github"
import { manifestEntry } from "../src/manifest"
import { RunStore } from "../src/run-store"
import { Store } from "../src/store"
import {
  BadBatchError,
  MAX_ATTEMPTS,
  MONTHLY_BATCH_LIMIT,
  type VerifierJob,
  type VerifierRunner,
  type VerifierVerdict,
  verifyPending,
} from "../src/verify"

const API = "https://api.test"
const SITE = "https://site.test"
const MIGRATIONS = new URL("../migrations/", import.meta.url).pathname
const LEVEL = "basic-motions-01"
const SETUP_LEVEL = "autocmds-01"
const DAY_MS = 86_400_000

const notUsed = (): Promise<never> => Promise.reject(new Error("GitHub isn't part of these tests"))
const github: GitHub = {
  startDevice: notUsed,
  pollDevice: notUsed,
  exchangeCode: notUsed,
  userId: notUsed,
}

function hashOf(level: string): string {
  const entry = manifestEntry(level)
  if (entry === undefined) {
    throw new Error(`${level} isn't in the manifest`)
  }
  return entry.hash
}

function runBody(keys: readonly string[], claimed = keys.length, level = LEVEL) {
  return {
    level_id: level,
    level_hash: hashOf(level),
    nvim: "0.12.6",
    keys,
    deltas_ms: keys.map(() => 100),
    claimed: { keys: claimed, seconds: keys.length / 10, hinted: false },
  }
}

describe("runs", () => {
  let db: D1Database
  let dispose: () => Promise<void>
  let app: App
  let runs: RunStore
  let now: number
  /** The sandbox's stand-in: what it was asked, and how it answers. */
  let jobsSeen: VerifierJob[][]
  let answer: (job: VerifierJob) => VerifierVerdict

  const runner: VerifierRunner = async (jobs) => {
    jobsSeen.push([...jobs])
    return jobs.map(answer)
  }
  const solveAll = (job: VerifierJob): VerifierVerdict => ({
    status: "solved",
    keys: job.keys.length,
  })

  beforeEach(async () => {
    const proxy = await getPlatformProxy<Env>({ persist: false })
    db = proxy.env.DB
    dispose = proxy.dispose
    for (const file of readdirSync(MIGRATIONS).sort()) {
      const sql = readFileSync(join(MIGRATIONS, file), "utf8").replace(/^\s*--.*$/gm, "")
      for (const statement of sql.split(";").filter((part) => part.trim() !== "")) {
        await db.prepare(statement).run()
      }
    }
    now = Date.UTC(2026, 9, 31)
    runs = new RunStore(db)
    app = {
      store: new Store(db),
      runs,
      github,
      config: { siteOrigin: SITE, apiOrigin: API, clientId: "c", rateLimitSalt: "s" },
      now: () => now,
    }
    jobsSeen = []
    answer = solveAll
  })

  afterEach(async () => {
    await dispose()
  })

  async function player(githubId: number): Promise<string> {
    const user = await app.store.userForGitHub(githubId, now)
    const token = `vdj_player-${githubId}`
    await app.store.insertToken({
      userId: user.id,
      tokenHash: await sha256Hex(token),
      kind: "plugin",
      now,
      expiresAt: now + 30 * DAY_MS,
    })
    return token
  }

  function call(method: string, path: string, token: string, body?: unknown): Promise<Response> {
    return handleRequest(
      new Request(`${API}${path}`, {
        method,
        headers: {
          authorization: `Bearer ${token}`,
          ...(body === undefined ? {} : { "content-type": "application/json" }),
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      }),
      app,
    )
  }

  async function submit(token: string, body: unknown): Promise<{ id: string; status: string }> {
    const response = await call("POST", "/api/v1/runs", token, body)
    return response.json()
  }

  async function statusOf(token: string, id: string) {
    const response = await call("GET", `/api/v1/runs/${id}`, token)
    return (await response.json()) as {
      status: string
      verified_keys: number | null
      claimed_keys: number
    }
  }

  const verify = (use: VerifierRunner = runner): Promise<void> => verifyPending(runs, use, now)

  async function bestOf(token: string): Promise<Array<{ keys: number; first_at: string }>> {
    const data = (await (await call("GET", "/api/v1/me/export", token)).json()) as {
      bests: Array<{ keys: number; first_at: string }>
    }
    return data.bests
  }

  describe("submitting", () => {
    it("needs a login", async () => {
      const response = await handleRequest(
        new Request(`${API}/api/v1/runs`, { method: "POST" }),
        app,
      )
      expect(response.status).toBe(401)
    })

    it("accepts a run for verifying", async () => {
      const token = await player(1)
      const response = await call("POST", "/api/v1/runs", token, runBody(["j", "l"]))
      expect(response.status).toBe(202)
      expect(((await response.json()) as { status: string }).status).toBe("pending")
    })

    it("treats the same keys as the same run", async () => {
      const token = await player(1)
      const first = await submit(token, runBody(["j", "l"]))
      const again = await call("POST", "/api/v1/runs", token, runBody(["j", "l"]))
      expect(again.status).toBe(200)
      expect(((await again.json()) as { id: string }).id).toBe(first.id)
      const { n } =
        (await db.prepare("SELECT count(*) AS n FROM runs").first<{ n: number }>()) ?? {}
      expect(n).toBe(1)
    })

    it("refuses a level that isn't shipped", async () => {
      const token = await player(1)
      const response = await call("POST", "/api/v1/runs", token, {
        ...runBody(["j"]),
        level_id: "my-custom-level",
      })
      expect(response.status).toBe(422)
      expect(((await response.json()) as { error: string }).error).toBe("unknown_level")
    })

    it("refuses a run on an older version of a level", async () => {
      const token = await player(1)
      const response = await call("POST", "/api/v1/runs", token, {
        ...runBody(["j"]),
        level_hash: "sha256:old",
      })
      expect(response.status).toBe(409)
      expect(((await response.json()) as { error: string }).error).toBe("level_changed")
    })

    it("stores a Setup run as unranked, and never replays it", async () => {
      const token = await player(1)
      const run = await submit(token, runBody(["i"], 1, SETUP_LEVEL))
      expect(run.status).toBe("unranked")
      await verify()
      expect(jobsSeen).toEqual([])
    })

    it("doesn't replay a run that doesn't claim to beat the player's best", async () => {
      const token = await player(1)
      await submit(token, runBody(["a", "b", "c"]))
      await verify()
      const worse = await submit(token, runBody(["a", "b", "c", "d"]))
      const tied = await submit(token, runBody(["x", "y", "z"]))
      expect([worse.status, tied.status]).toEqual(["not_best", "not_best"])
    })

    it.each([
      ["a gap missing", { ...runBody(["j", "k"]), deltas_ms: [1] }],
      ["no keys", { ...runBody(["j"]), keys: [], deltas_ms: [] }],
      ["too many keys", runBody(Array.from({ length: 2001 }, () => "j"))],
      ["a negative gap", { ...runBody(["j"]), deltas_ms: [-1] }],
      ["a key that is far too long", runBody(["x".repeat(33)])],
    ])("refuses a body with %s", async (_name, body) => {
      const response = await call("POST", "/api/v1/runs", await player(1), body)
      expect([413, 422]).toContain(response.status)
    })

    it("limits runs per minute", async () => {
      const token = await player(1)
      const statuses: number[] = []
      for (let i = 0; i < 31; i++) {
        statuses.push((await call("POST", "/api/v1/runs", token, runBody([`k${i}`]))).status)
      }
      expect(statuses.slice(0, 30).every((status) => status === 202)).toBe(true)
      expect(statuses[30]).toBe(429)
    })
  })

  describe("reading a run", () => {
    it("shows the owner the result, without the keys", async () => {
      const token = await player(1)
      const { id } = await submit(token, runBody(["j", "l"]))
      const text = await (await call("GET", `/api/v1/runs/${id}`, token)).text()
      expect(text).toContain('"status":"pending"')
      expect(text).not.toContain('"keys":[')
    })

    it("hides a run from everyone else: it's that level's solution", async () => {
      const { id } = await submit(await player(1), runBody(["j", "l"]))
      expect((await call("GET", `/api/v1/runs/${id}`, await player(2))).status).toBe(404)
    })
  })

  describe("verifying", () => {
    it("verifies an honest run and records the best", async () => {
      const token = await player(1)
      const { id } = await submit(token, runBody(["j", "l"]))
      await verify()
      expect(await statusOf(token, id)).toMatchObject({ status: "verified", verified_keys: 2 })
      expect((await bestOf(token))[0]?.keys).toBe(2)
    })

    it("ranks a forged count at the verifier's count", async () => {
      const token = await player(1)
      const { id } = await submit(token, runBody(["j", "j", "j", "l", "l"], 1))
      await verify()
      expect(await statusOf(token, id)).toMatchObject({
        status: "mismatch",
        claimed_keys: 1,
        verified_keys: 5,
      })
      expect((await bestOf(token))[0]?.keys).toBe(5)
    })

    it("rejects a log that doesn't solve the level, and records no best", async () => {
      const token = await player(1)
      const { id } = await submit(token, runBody(["j"]))
      answer = () => ({ status: "unsolved" })
      await verify()
      expect((await statusOf(token, id)).status).toBe("rejected")
      expect(await bestOf(token)).toEqual([])
    })

    it("sends the sandbox nothing about who played", async () => {
      const token = await player(4242)
      await submit(token, runBody(["j", "l"]))
      await verify()
      expect(jobsSeen[0]).toEqual([
        { level_id: LEVEL, level_hash: hashOf(LEVEL), keys: ["j", "l"] },
      ])
    })

    it("replays identical logs once, across players", async () => {
      const first = await player(1)
      const second = await player(2)
      await submit(first, runBody(["j", "l"]))
      await verify()
      const { id } = await submit(second, runBody(["j", "l"]))
      await verify()
      expect(jobsSeen).toHaveLength(1)
      expect(await statusOf(second, id)).toMatchObject({ status: "verified", verified_keys: 2 })
    })

    it("keeps players in separate batches", async () => {
      await submit(await player(1), runBody(["a"]))
      now += 1000
      await submit(await player(2), runBody(["b"]))
      await verify()
      expect(jobsSeen.map((jobs) => jobs.map((job) => job.keys[0]))).toEqual([["a"], ["b"]])
    })

    it("doesn't let one player's backlog starve another", async () => {
      const busy = await player(1)
      for (let i = 0; i < 25; i++) {
        await submit(busy, runBody(Array.from({ length: 30 - i }, () => "j")))
      }
      now += 1000
      const patient = await player(2)
      const { id } = await submit(patient, runBody(["z"]))
      await verify()
      expect((await statusOf(patient, id)).status).toBe("verified")
    })

    it("keeps the lower count, and the earlier run on a tie", async () => {
      const token = await player(1)
      await submit(token, runBody(["a", "b", "c"]))
      await verify()
      const [first] = await bestOf(token)
      now += 60_000
      await submit(token, runBody(["d", "e"]))
      await verify()
      const [better] = await bestOf(token)
      expect(better?.keys).toBe(2)
      expect(better?.first_at).not.toBe(first?.first_at)

      // Claims 1, but really takes 2: it reaches the verifier and ties.
      now += 60_000
      await submit(token, runBody(["f", "g"], 1))
      await verify()
      expect((await bestOf(token))[0]?.first_at).toBe(better?.first_at)
    })

    it("stops retrying a log that keeps erroring, and spares the others", async () => {
      const token = await player(1)
      const bad = await submit(token, runBody(["bad"]))
      const good = await submit(token, runBody(["g", "o", "o", "d"]))
      answer = (job) =>
        job.keys[0] === "bad" ? { status: "error", reason: "timed out" } : solveAll(job)
      for (let i = 0; i < MAX_ATTEMPTS; i++) {
        await verify()
      }
      expect((await statusOf(token, bad.id)).status).toBe("failed")
      expect((await statusOf(token, good.id)).status).toBe("verified")
      const replays = jobsSeen.flat().filter((job) => job.keys[0] === "bad")
      expect(replays).toHaveLength(MAX_ATTEMPTS)
    })

    it("counts a broken batch against its runs, so it can't loop forever", async () => {
      const token = await player(1)
      const { id } = await submit(token, runBody(["j"]))
      const broken: VerifierRunner = () => Promise.reject(new BadBatchError("bad output"))
      for (let i = 0; i < MAX_ATTEMPTS; i++) {
        await verify(broken)
      }
      expect((await statusOf(token, id)).status).toBe("failed")
    })

    it("treats too few verdicts as a broken batch", async () => {
      const token = await player(1)
      const { id } = await submit(token, runBody(["j"]))
      for (let i = 0; i < MAX_ATTEMPTS; i++) {
        await verify(() => Promise.resolve([]))
      }
      expect((await statusOf(token, id)).status).toBe("failed")
    })

    it("keeps runs pending through an outage, at no cost to them", async () => {
      const token = await player(1)
      const { id } = await submit(token, runBody(["j"]))
      const down: VerifierRunner = () => Promise.reject(new Error("Vercel is down"))
      for (let i = 0; i < MAX_ATTEMPTS + 2; i++) {
        await verify(down)
      }
      expect((await statusOf(token, id)).status).toBe("pending")
      await verify()
      expect((await statusOf(token, id)).status).toBe("verified")
    })

    it("carries on with the next player after one batch fails", async () => {
      await submit(await player(1), runBody(["a"]))
      const second = await player(2)
      const { id } = await submit(second, runBody(["b"]))
      await verify((jobs) =>
        jobs[0]?.keys[0] === "a" ? Promise.reject(new Error("down")) : runner(jobs),
      )
      expect((await statusOf(second, id)).status).toBe("verified")
    })

    it("stops at the monthly limit, and resumes next month", async () => {
      const token = await player(1)
      const { id } = await submit(token, runBody(["j"]))
      await db
        .prepare("INSERT INTO verifier_usage (month, batches) VALUES ('2026-10', ?)")
        .bind(MONTHLY_BATCH_LIMIT)
        .run()
      await verify()
      expect(jobsSeen).toEqual([])
      expect((await statusOf(token, id)).status).toBe("pending")
      now = Date.UTC(2026, 10, 1)
      await verify()
      expect((await statusOf(token, id)).status).toBe("verified")
    })
  })

  describe("the player's data", () => {
    it("exports their runs and bests, with the keys", async () => {
      const token = await player(1)
      await submit(token, runBody(["j", "l"]))
      await verify()
      const data = (await (await call("GET", "/api/v1/me/export", token)).json()) as {
        runs: Array<{ keys: string[]; status: string }>
        bests: unknown[]
      }
      expect(data.runs[0]).toMatchObject({ keys: ["j", "l"], status: "verified" })
      expect(data.bests).toHaveLength(1)
    })

    it("deletes runs and bests with the account", async () => {
      const token = await player(1)
      await submit(token, runBody(["j", "l"]))
      await verify()
      const response = await call("DELETE", "/api/v1/me", token, { confirm: "delete my account" })
      expect(response.status).toBe(204)
      const count = async (table: string): Promise<unknown> =>
        (await db.prepare(`SELECT count(*) AS n FROM ${table}`).first<{ n: number }>())?.n
      expect(await count("runs")).toBe(0)
      expect(await count("bests")).toBe(0)
    })

    it("expires old runs, but keeps the one behind a best", async () => {
      const token = await player(1)
      const best = await submit(token, runBody(["a"]))
      await verify()
      const other = await submit(token, runBody(["b", "c"]))
      await verify()
      now += 91 * DAY_MS
      await sweep(app)
      const { results } = await db.prepare("SELECT id FROM runs").all<{ id: string }>()
      expect(results.map((row) => row.id)).toEqual([best.id])
      expect(results.map((row) => row.id)).not.toContain(other.id)
    })
  })
})
