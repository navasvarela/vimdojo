// Line-for-line port of lua/vimdojo/scoring.lua. Keep the order of floating
// point operations identical so both produce the same rounding; both are
// tested against tests/fixtures/scoring.json.

export const MAX_POINTS = 1000
export const KEY_WEIGHT = 0.7
export const TIME_WEIGHT = 0.3
export const TWO_STAR_KEY_FACTOR = 1.5
export const HINT_POINTS_FACTOR = 0.8
export const HINTED_MAX_STARS = 2

export type Stars = 1 | 2 | 3

export type Attempt = {
  readonly keys: number
  readonly seconds: number
  readonly par_keys: number
  readonly par_seconds: number
  readonly hinted: boolean
}

export type Score = {
  readonly stars: Stars
  readonly points: number
}

/** 1 when at or under par, otherwise the fraction of par achieved. */
function parRatio(par: number, actual: number): number {
  if (actual <= par) {
    return 1
  }
  return par / actual
}

export function stars(attempt: Attempt): Stars {
  let earned: Stars = 1
  if (attempt.keys <= attempt.par_keys && attempt.seconds <= attempt.par_seconds) {
    earned = 3
  } else if (attempt.keys <= attempt.par_keys * TWO_STAR_KEY_FACTOR) {
    earned = 2
  }
  if (attempt.hinted && earned > HINTED_MAX_STARS) {
    return HINTED_MAX_STARS
  }
  return earned
}

export function points(attempt: Attempt): number {
  const keyPart = KEY_WEIGHT * parRatio(attempt.par_keys, attempt.keys)
  const timePart = TIME_WEIGHT * parRatio(attempt.par_seconds, attempt.seconds)
  let raw = MAX_POINTS * (keyPart + timePart)
  if (attempt.hinted) {
    raw = raw * HINT_POINTS_FACTOR
  }
  return Math.floor(raw + 0.5)
}

export function score(attempt: Attempt): Score {
  return { stars: stars(attempt), points: points(attempt) }
}
