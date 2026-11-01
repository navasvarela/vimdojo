/** Key notation spells a typed "<" as "<lt>", which reads as a command to a player. */
export function readableKeys(keys: string): string {
  return keys.replaceAll("<lt>", "<")
}

/** Showing the par route on today's daily would let anyone copy their way up the board. */
export const SOLUTION_HIDDEN = "Shown once today's daily ends (00:00 UTC)."
