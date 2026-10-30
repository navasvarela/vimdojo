// The daily challenge, ported from lua/vimdojo/daily.lua: one level per UTC
// day, the same in both clients. tests/fixtures/daily.json pins both.
import type { Pack } from "./challenges"

const MS_PER_DAY = 86_400_000

// Park-Miller MINSTD: products stay below 2^47, so JavaScript numbers and
// Lua's doubles compute them exactly. Must match daily.lua.
const MODULUS = 2_147_483_647
const MULTIPLIER = 48_271

/** The demo levels, sorted by id (see `M.pool` in daily.lua). */
export function dailyPool(packs: readonly Pack[]): string[] {
  return packs
    .flatMap((pack) => pack.levels)
    .filter((level) => level.web_demo === true)
    .map((level) => level.id)
    .sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
}

/** Days since 1970-01-01 UTC. */
export function dayNumber(epochMs: number): number {
  return Math.floor(epochMs / MS_PER_DAY)
}

/** "YYYY-MM-DD", UTC. */
export function dailyDate(day: number): string {
  return new Date(day * MS_PER_DAY).toISOString().slice(0, 10)
}

function swap(order: string[], i: number, j: number): void {
  const first = order[i]
  const second = order[j]
  if (first === undefined || second === undefined) {
    throw new Error(`unreachable: positions ${i} and ${j} are inside the pool`)
  }
  order[i] = second
  order[j] = first
}

function shuffled(pool: readonly string[], cycle: number): string[] {
  const order = [...pool]
  let seed = (cycle % (MODULUS - 1)) + 1
  for (let i = order.length - 1; i >= 1; i--) {
    seed = (seed * MULTIPLIER) % MODULUS
    swap(order, i, seed % (i + 1))
  }
  return order
}

/**
 * Every level once per cycle of `pool.length` days, shuffled per cycle, and
 * never the same level two days running (see `M.pick` in daily.lua).
 */
export function pickDaily(pool: readonly string[], day: number): string | undefined {
  const size = pool.length
  if (size === 0) {
    return undefined
  }
  const cycle = Math.floor(day / size)
  const order = shuffled(pool, cycle)
  if (size > 2 && cycle > 0 && order[0] === shuffled(pool, cycle - 1)[size - 1]) {
    swap(order, 0, 1)
  }
  return order[day % size]
}
