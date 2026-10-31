// All SQL lives here. Times are milliseconds since the epoch.
import { randomId } from "./crypto"

export type UserRow = {
  readonly id: string
  readonly github_id: number
  readonly handle: string | null
  readonly handle_changed_at: number | null
  readonly created_at: number
}

export type TokenKind = "web" | "plugin"

export type TokenRow = {
  readonly id: string
  readonly user_id: string
  readonly kind: TokenKind
  readonly created_at: number
  readonly last_used_at: number
  readonly expires_at: number
}

export type TokenWithUser = TokenRow & { readonly user: UserRow }

export type NewToken = {
  readonly userId: string
  readonly tokenHash: string
  readonly kind: TokenKind
  readonly now: number
  readonly expiresAt: number
}

export class Store {
  constructor(private readonly db: D1Database) {}

  /** Finds the account for a GitHub id, creating it at first login. */
  async userForGitHub(githubId: number, now: number): Promise<UserRow> {
    await this.db
      .prepare(
        "INSERT INTO users (id, github_id, created_at) VALUES (?, ?, ?) ON CONFLICT (github_id) DO NOTHING",
      )
      .bind(randomId(), githubId, now)
      .run()
    const user = await this.db
      .prepare("SELECT * FROM users WHERE github_id = ?")
      .bind(githubId)
      .first<UserRow>()
    if (user === null) {
      throw new Error("unreachable: the user was just created")
    }
    return user
  }

  async insertToken(token: NewToken): Promise<void> {
    await this.db
      .prepare(
        "INSERT INTO tokens (id, user_id, token_hash, kind, created_at, last_used_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      )
      .bind(
        randomId(),
        token.userId,
        token.tokenHash,
        token.kind,
        token.now,
        token.now,
        token.expiresAt,
      )
      .run()
  }

  async tokenByHash(tokenHash: string, now: number): Promise<TokenWithUser | undefined> {
    const row = await this.db
      .prepare(
        `SELECT t.id, t.user_id, t.kind, t.created_at, t.last_used_at, t.expires_at,
                u.github_id, u.handle, u.handle_changed_at, u.created_at AS user_created_at
         FROM tokens t JOIN users u ON u.id = t.user_id
         WHERE t.token_hash = ? AND t.expires_at > ?`,
      )
      .bind(tokenHash, now)
      .first<TokenRow & Omit<UserRow, "id" | "created_at"> & { user_created_at: number }>()
    if (row === null) {
      return undefined
    }
    return {
      id: row.id,
      user_id: row.user_id,
      kind: row.kind,
      created_at: row.created_at,
      last_used_at: row.last_used_at,
      expires_at: row.expires_at,
      user: {
        id: row.user_id,
        github_id: row.github_id,
        handle: row.handle,
        handle_changed_at: row.handle_changed_at,
        created_at: row.user_created_at,
      },
    }
  }

  async touchToken(tokenId: string, now: number, expiresAt: number): Promise<void> {
    await this.db
      .prepare("UPDATE tokens SET last_used_at = ?, expires_at = ? WHERE id = ?")
      .bind(now, expiresAt, tokenId)
      .run()
  }

  async tokensOf(userId: string, now: number): Promise<readonly TokenRow[]> {
    const { results } = await this.db
      .prepare(
        "SELECT id, user_id, kind, created_at, last_used_at, expires_at FROM tokens WHERE user_id = ? AND expires_at > ? ORDER BY created_at",
      )
      .bind(userId, now)
      .all<TokenRow>()
    return results
  }

  /** Scoped to the owner, so one player can't revoke another's token by id. */
  async deleteToken(userId: string, tokenId: string): Promise<boolean> {
    const result = await this.db
      .prepare("DELETE FROM tokens WHERE id = ? AND user_id = ?")
      .bind(tokenId, userId)
      .run()
    return result.meta.changes > 0
  }

  async isHandleHeld(handle: string, now: number): Promise<boolean> {
    const row = await this.db
      .prepare("SELECT 1 AS held FROM handle_holds WHERE handle = ? AND held_until > ?")
      .bind(handle, now)
      .first()
    return row !== null
  }

  private holdStatement(handle: string, heldUntil: number): D1PreparedStatement {
    return this.db
      .prepare(
        "INSERT INTO handle_holds (handle, held_until) VALUES (?, ?) ON CONFLICT (handle) DO UPDATE SET held_until = excluded.held_until",
      )
      .bind(handle, heldUntil)
  }

  /** @returns false when another account has the handle. Atomic with the hold. */
  async setHandle(user: UserRow, handle: string, now: number, heldUntil: number): Promise<boolean> {
    const update = this.db
      .prepare("UPDATE users SET handle = ?, handle_changed_at = ? WHERE id = ?")
      .bind(handle, now, user.id)
    try {
      await this.db.batch(
        user.handle === null ? [update] : [this.holdStatement(user.handle, heldUntil), update],
      )
      return true
    } catch (error) {
      if (error instanceof Error && error.message.includes("UNIQUE")) {
        return false
      }
      throw error
    }
  }

  /** Tokens go with the user (ON DELETE CASCADE); the hold keeps no link to them. */
  async deleteUser(user: UserRow, heldUntil: number): Promise<void> {
    const remove = this.db.prepare("DELETE FROM users WHERE id = ?").bind(user.id)
    await this.db.batch(
      user.handle === null ? [remove] : [this.holdStatement(user.handle, heldUntil), remove],
    )
  }

  async insertDeviceLogin(deviceCode: string, expiresAt: number): Promise<string> {
    const id = randomId()
    await this.db
      .prepare("INSERT INTO device_logins (id, device_code, expires_at) VALUES (?, ?, ?)")
      .bind(id, deviceCode, expiresAt)
      .run()
    return id
  }

  async deviceCode(id: string, now: number): Promise<string | undefined> {
    const row = await this.db
      .prepare("SELECT device_code FROM device_logins WHERE id = ? AND expires_at > ?")
      .bind(id, now)
      .first<{ device_code: string }>()
    return row?.device_code
  }

  async deleteDeviceLogin(id: string): Promise<void> {
    await this.db.prepare("DELETE FROM device_logins WHERE id = ?").bind(id).run()
  }

  /** Counts one request and returns the window's total. */
  async countRequest(subject: string, windowStart: number): Promise<number> {
    const row = await this.db
      .prepare(
        `INSERT INTO rate_limits (subject, window_start, count) VALUES (?, ?, 1)
         ON CONFLICT (subject, window_start) DO UPDATE SET count = count + 1
         RETURNING count`,
      )
      .bind(subject, windowStart)
      .first<{ count: number }>()
    return row?.count ?? 1
  }

  /** Removes what has expired. Run daily, so personal data doesn't linger. */
  async sweep(now: number, rateLimitsBefore: number): Promise<void> {
    await this.db.batch([
      this.db.prepare("DELETE FROM tokens WHERE expires_at <= ?").bind(now),
      this.db.prepare("DELETE FROM device_logins WHERE expires_at <= ?").bind(now),
      this.db.prepare("DELETE FROM handle_holds WHERE held_until <= ?").bind(now),
      this.db.prepare("DELETE FROM rate_limits WHERE window_start < ?").bind(rateLimitsBefore),
    ])
  }
}
