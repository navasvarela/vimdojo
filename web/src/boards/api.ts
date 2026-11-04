// Reads for the boards pages. Boards and profiles are public, so only the player's
// own place sends the session cookie. Responses are checked at this edge.
import { z } from "zod"
import { apiOrigin } from "../account/api"

const Board = z.object({
  entries: z.array(
    z.object({
      rank: z.number(),
      handle: z.string(),
      keys: z.number(),
      hinted: z.boolean(),
      since: z.string(),
    }),
  ),
})
export type BoardEntry = z.infer<typeof Board>["entries"][number]

const DailyBoard = z.object({
  date: z.string(),
  level_id: z.string(),
  entries: z.array(
    z.object({ rank: z.number(), handle: z.string(), keys: z.number(), hinted: z.boolean() }),
  ),
})
export type DailyBoard = z.infer<typeof DailyBoard>

const OwnRank = z.object({ rank: z.number().nullable(), keys: z.number().nullable() })
export type OwnRank = z.infer<typeof OwnRank>

const OverallEntry = z.object({
  rank: z.number(),
  handle: z.string(),
  solved: z.number(),
  over_par: z.number(),
})
export type OverallEntry = z.infer<typeof OverallEntry>

const Overall = z.object({ entries: z.array(OverallEntry) })

const OwnOverall = z.object({
  rank: z.number().nullable(),
  solved: z.number().nullable(),
  over_par: z.number().nullable(),
})
export type OwnOverall = z.infer<typeof OwnOverall>

const Player = z.object({
  handle: z.string(),
  joined: z.string(),
  // Older API versions don't send it.
  overall: OverallEntry.nullable().default(null),
  bests: z.array(
    z.object({ level_id: z.string(), keys: z.number(), hinted: z.boolean(), since: z.string() }),
  ),
})
export type Player = z.infer<typeof Player>

const HTTP_NOT_FOUND = 404

type Fetch = typeof fetch

export class BoardsApi {
  constructor(private readonly fetcher: Fetch = (...args) => fetch(...args)) {}

  async board(levelId: string): Promise<readonly BoardEntry[]> {
    const response = await this.fetcher(
      `${apiOrigin()}/api/v1/levels/${encodeURIComponent(levelId)}/board`,
    )
    if (!response.ok) {
      throw new Error(`the board answered ${response.status}`)
    }
    return Board.parse(await response.json()).entries
  }

  /** @returns undefined when signed out: that's normal here, not a failure. */
  async ownRank(levelId: string): Promise<OwnRank | undefined> {
    const response = await this.fetcher(
      `${apiOrigin()}/api/v1/levels/${encodeURIComponent(levelId)}/board/me`,
      { credentials: "include" },
    )
    return response.ok ? OwnRank.parse(await response.json()) : undefined
  }

  /** @returns undefined when there's no board for that day. */
  async daily(date: string | undefined): Promise<DailyBoard | undefined> {
    const day = date === undefined ? "" : `/${encodeURIComponent(date)}`
    const response = await this.fetcher(`${apiOrigin()}/api/v1/daily${day}`)
    if (response.status === HTTP_NOT_FOUND) {
      return undefined
    }
    if (!response.ok) {
      throw new Error(`the daily board answered ${response.status}`)
    }
    return DailyBoard.parse(await response.json())
  }

  /** @returns undefined when signed out: that's normal here, not a failure. */
  async ownDailyRank(): Promise<OwnRank | undefined> {
    const response = await this.fetcher(`${apiOrigin()}/api/v1/daily/me`, {
      credentials: "include",
    })
    return response.ok ? OwnRank.parse(await response.json()) : undefined
  }

  async overall(): Promise<readonly OverallEntry[]> {
    const response = await this.fetcher(`${apiOrigin()}/api/v1/overall`)
    if (!response.ok) {
      throw new Error(`the overall board answered ${response.status}`)
    }
    return Overall.parse(await response.json()).entries
  }

  /** @returns undefined when signed out: that's normal here, not a failure. */
  async ownOverall(): Promise<OwnOverall | undefined> {
    const response = await this.fetcher(`${apiOrigin()}/api/v1/overall/me`, {
      credentials: "include",
    })
    return response.ok ? OwnOverall.parse(await response.json()) : undefined
  }

  /** @returns undefined when no player has that handle. */
  async player(handle: string): Promise<Player | undefined> {
    const response = await this.fetcher(
      `${apiOrigin()}/api/v1/players/${encodeURIComponent(handle)}`,
    )
    if (response.status === HTTP_NOT_FOUND) {
      return undefined
    }
    if (!response.ok) {
      throw new Error(`the profile answered ${response.status}`)
    }
    return Player.parse(await response.json())
  }
}
