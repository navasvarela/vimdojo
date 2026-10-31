// Builds the verifier's Vercel Sandbox snapshot: a microVM in Frankfurt with
// a pinned Neovim, vimdojo's Lua and the bundled harness, its network then
// cut off. The API resumes this snapshot for every verification batch.
//
// Usage (from verifier/, after `npm run build`):
//   VERCEL_TOKEN=... VERCEL_TEAM_ID=... VERCEL_PROJECT_ID=... \
//     node dist/build-snapshot.js
// Prints the snapshot id to store as the API's VERIFIER_SNAPSHOT_ID.
import { readdir, readFile } from "node:fs/promises"
import { join, relative } from "node:path"
import { fileURLToPath } from "node:url"
import { Sandbox } from "@vercel/sandbox"
import { env, REGION, SANDBOX_PATHS } from "./config"

const ROOT = fileURLToPath(new URL("../..", import.meta.url))

// Neovim 0.12.6, the stable release the reference solutions are verified on.
// The digests come from the release's asset list; a replaced download fails.
const NVIM_VERSION = "v0.12.6"
const NVIM_BUILDS: Readonly<Record<string, { asset: string; sha256: string }>> = {
  x86_64: {
    asset: "nvim-linux-x86_64",
    sha256: "474430d53e6264f6d6dd18db42d6dc9df3a1b56ca9e88a325bbf860e1a811d87",
  },
  aarch64: {
    asset: "nvim-linux-arm64",
    sha256: "8f1f64a0bdb97247034038c3823c6cbad5bdf9ecd5751b85494b71c3ee04c815",
  },
}

async function filesUnder(dir: string): Promise<string[]> {
  const entries = await readdir(dir, { recursive: true, withFileTypes: true })
  return entries
    .filter((entry) => entry.isFile())
    .map((entry) => join(entry.parentPath, entry.name))
}

async function run(sandbox: Sandbox, cmd: string, args: string[], sudo = false): Promise<string> {
  const result = await sandbox.runCommand({ cmd, args, sudo })
  const output = await result.output("both")
  if (result.exitCode !== 0) {
    throw new Error(`${cmd} ${args.join(" ")} failed (${result.exitCode}):\n${output}`)
  }
  return output
}

async function installNeovim(sandbox: Sandbox): Promise<void> {
  const arch = (await run(sandbox, "uname", ["-m"])).trim()
  const build = NVIM_BUILDS[arch]
  if (build === undefined) {
    throw new Error(`no pinned Neovim build for ${arch}`)
  }
  const url = `https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${build.asset}.tar.gz`
  await run(sandbox, "curl", ["-fsSL", "-o", "/tmp/nvim.tar.gz", url])
  await run(sandbox, "sh", ["-c", `echo "${build.sha256}  /tmp/nvim.tar.gz" | sha256sum -c -`])
  await run(sandbox, "mkdir", ["-p", "/opt/nvim"], true)
  await run(
    sandbox,
    "tar",
    ["-xzf", "/tmp/nvim.tar.gz", "-C", "/opt/nvim", "--strip-components=1"],
    true,
  )
  console.log(await run(sandbox, SANDBOX_PATHS.nvim, ["--version"]))
}

async function uploadVerifier(sandbox: Sandbox): Promise<void> {
  const luaFiles = await filesUnder(join(ROOT, "lua"))
  const files = await Promise.all(
    luaFiles.map(async (path) => ({
      path: `${SANDBOX_PATHS.plugin}/${relative(ROOT, path)}`,
      content: await readFile(path),
    })),
  )
  const levelFiles = (await readdir(join(ROOT, "challenges"))).filter((n) => /^\d.*\.json$/.test(n))
  for (const name of levelFiles) {
    files.push({
      path: `${SANDBOX_PATHS.plugin}/challenges/${name}`,
      content: await readFile(join(ROOT, "challenges", name)),
    })
  }
  files.push({
    path: SANDBOX_PATHS.cli,
    content: await readFile(join(ROOT, "verifier/dist/cli.js")),
  })
  await sandbox.writeFiles(files)
  // The replay user has to read the plugin, and can't write to any of it.
  const pluginDir = (await run(sandbox, "realpath", [SANDBOX_PATHS.plugin])).trim()
  await run(sandbox, "chown", ["-R", "root:root", pluginDir], true)
  await run(sandbox, "chmod", ["-R", "a+rX,go-w", pluginDir], true)
  await run(sandbox, "sh", ["-c", `namei -m ${pluginDir} | cat`])
}

/** The unprivileged user each replay runs as. No home: each job makes its own. */
async function createReplayUser(sandbox: Sandbox): Promise<void> {
  await run(
    sandbox,
    "useradd",
    ["--no-create-home", "--shell", "/sbin/nologin", SANDBOX_PATHS.replayUser],
    true,
  )
}

async function main(): Promise<void> {
  const sandbox = await Sandbox.create({
    token: env("VERCEL_TOKEN"),
    teamId: env("VERCEL_TEAM_ID"),
    projectId: env("VERCEL_PROJECT_ID"),
    region: REGION,
    runtime: "node22",
    resources: { vcpus: 1 },
    timeout: 10 * 60 * 1000,
  })
  try {
    await installNeovim(sandbox)
    await uploadVerifier(sandbox)
    await createReplayUser(sandbox)
    // Replayed keys can run shell commands, so the snapshot has no network.
    await sandbox.updateNetworkPolicy("deny-all")
    // No expiration: the API resumes this snapshot until it's rebuilt.
    const snapshot = await sandbox.snapshot({ expiration: 0 })
    console.log(`VERIFIER_SNAPSHOT_ID=${snapshot.snapshotId}`)
  } catch (error) {
    await sandbox.stop()
    throw error
  }
}

await main()
