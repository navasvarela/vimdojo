// Shared by the snapshot builder and the batch runner (and later the API).

// Keeps player data and replays in the EU (PLAN-v3, L10).
export const REGION = "fra1"

/** Paths inside the sandbox, relative to its working directory. */
export const SANDBOX_PATHS = {
  plugin: "vimdojo",
  cli: "vimdojo/cli.js",
  nvim: "/opt/nvim/bin/nvim",
} as const

export function env(name: string): string {
  const value = process.env[name]
  if (value === undefined || value === "") {
    throw new Error(`${name} is not set`)
  }
  return value
}
