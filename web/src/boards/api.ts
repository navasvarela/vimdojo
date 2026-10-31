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

const OwnRank = z.object({ rank: z.number().nullable(), keys: z.number().nullable() })
export type OwnRank = z.infer<typeof OwnRank>

const Player = z.object({
  handle: z.string(),
  joined: z.string(),
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
