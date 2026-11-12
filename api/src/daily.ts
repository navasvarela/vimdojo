// Which level is the daily challenge on a given UTC day. The picker itself is the
// site's (web/src/daily.ts), so the API, the site and the plugin all agree: the
// shared fixture pins it against the plugin's Lua port.
import { dailyDate, dailyLevel, dayNumber } from "../../web/src/daily"
import { DAILY_SCHEDULE } from "./manifest"

export type Daily = { readonly date: string; readonly levelId: string }

function dailyOn(day: number): Daily | undefined {
  const levelId = dailyLevel(DAILY_SCHEDULE, day)
  return levelId === undefined ? undefined : { date: dailyDate(day), levelId }
}

/** The UTC day a moment falls on, as the boards name it. */
export function dailyDateOf(at: number): string {
  return dailyDate(dayNumber(at))
}

export function todaysDaily(now: number): Daily | undefined {
  return dailyOn(dayNumber(now))
}

/** @returns undefined for a date that isn't real, or hasn't happened yet. */
export function dailyForDate(date: string, now: number): Daily | undefined {
  const ms = Date.parse(`${date}T00:00:00Z`)
  if (Number.isNaN(ms) || new Date(ms).toISOString().slice(0, 10) !== date || ms > now) {
    return undefined
  }
  return dailyOn(dayNumber(ms))
}
