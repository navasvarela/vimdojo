// "Beat my keys" links: https://vimdojo.org/?play=<level>&beat=<keys>. A copied result
// (share.lua, share.ts) links to the level's share page, /play/<level>/?beat=<keys>,
// which forwards here. Links copied before the share pages existed come here directly.
// The query is untrusted, so it's checked here and the rest of the site only sees a
// valid challenge.

export type Challenge = { readonly levelId: string; readonly keys: number }

const LEVEL_ID = /^[a-z0-9-]{1,64}$/
const KEYS = /^[1-9]\d{0,3}$/

export function parseChallenge(search: string): Challenge | undefined {
  const params = new URLSearchParams(search)
  const levelId = params.get("play") ?? ""
  const keys = params.get("beat") ?? ""
  if (!LEVEL_ID.test(levelId) || !KEYS.test(keys)) {
    return undefined
  }
  return { levelId, keys: Number(keys) }
}

/** How the player's count compares, for the results card. */
export function challengeResult(challenge: Challenge, keys: number): string {
  const difference = challenge.keys - keys
  if (difference > 0) {
    return `You beat ${challenge.keys} keys by ${difference}. Send them yours.`
  }
  if (difference === 0) {
    return `You matched ${challenge.keys} keys.`
  }
  return `${-difference} over ${challenge.keys} keys. Retry (R) to beat it.`
}
