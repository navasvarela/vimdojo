// Which levels exist and how they rank, from the committed manifest. The level
// data itself stays out of the Worker: the verifier reads it from its own copy.
import manifest from "../../verifier/manifest.json"

export type ManifestEntry = { readonly hash: string; readonly ranked: boolean }

const LEVELS: ReadonlyMap<string, ManifestEntry> = new Map(Object.entries(manifest.levels))

export function manifestEntry(levelId: string): ManifestEntry | undefined {
  return LEVELS.get(levelId)
}
