import { emptyProgress, parseProgress, type Progress } from "./progress"

const STORAGE_KEY = "vimdojo.progress"
export const EXPORT_FILE_NAME = "progress.json"

export type LoadResult =
  | { readonly status: "loaded"; readonly progress: Progress }
  | { readonly status: "empty"; readonly progress: Progress }
  | { readonly status: "unavailable"; readonly progress: Progress }
  | { readonly status: "corrupt"; readonly progress: Progress }

/** Never throws: storage can be disabled, full, or hold garbage from an old version. */
export function loadProgress(storage: Storage | undefined): LoadResult {
  let raw: string | null
  try {
    if (storage === undefined) {
      return { status: "unavailable", progress: emptyProgress() }
    }
    raw = storage.getItem(STORAGE_KEY)
  } catch {
    return { status: "unavailable", progress: emptyProgress() }
  }
  if (raw === null) {
    return { status: "empty", progress: emptyProgress() }
  }
  const progress = parseJsonProgress(raw)
  return progress === undefined
    ? { status: "corrupt", progress: emptyProgress() }
    : { status: "loaded", progress }
}

/** Returns false when the progress could not be persisted (storage disabled or full). */
export function saveProgress(storage: Storage | undefined, progress: Progress): boolean {
  try {
    if (storage === undefined) {
      return false
    }
    storage.setItem(STORAGE_KEY, serializeProgress(progress))
    return true
  } catch {
    return false
  }
}

export function serializeProgress(progress: Progress): string {
  return JSON.stringify(progress, null, 2)
}

export function parseJsonProgress(text: string): Progress | undefined {
  try {
    return parseProgress(JSON.parse(text))
  } catch {
    return undefined
  }
}

/** window.localStorage, or undefined when merely touching it throws (some privacy modes). */
export function browserStorage(): Storage | undefined {
  try {
    return window.localStorage
  } catch {
    return undefined
  }
}
