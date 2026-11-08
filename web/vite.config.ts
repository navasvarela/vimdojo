import { fileURLToPath } from "node:url"
import { playwright } from "@vitest/browser-playwright"
import { defineConfig } from "vitest/config"
import { analyticsPlugin } from "./build/analytics"
import { boardLevelsPlugin } from "./build/board-levels"
import { accountCspPlugin } from "./build/csp"
import { curriculumPlugin } from "./build/curriculum"
import { shareCardsPlugin } from "./build/share-pages"
import { SITE_URL } from "./src/share"

const CHALLENGES_DIR = fileURLToPath(new URL("../challenges", import.meta.url))
const INDEX_HTML = fileURLToPath(new URL("index.html", import.meta.url))
const ACCOUNT_HTML = fileURLToPath(new URL("account/index.html", import.meta.url))
const PRIVACY_HTML = fileURLToPath(new URL("privacy/index.html", import.meta.url))
const BOARDS_HTML = fileURLToPath(new URL("boards/index.html", import.meta.url))
const PLAYER_HTML = fileURLToPath(new URL("player/index.html", import.meta.url))
const SHARE_IMAGE = fileURLToPath(new URL("../docs/brand/social-preview.png", import.meta.url))
const API_ORIGIN = process.env["VITE_API_URL"] ?? "https://api.vimdojo.org"

// The site is served from the root of its custom domain (vimdojo.org).
// Set VITE_BASE=/<repo-name>/ to serve it from a github.io project page instead.
const DEFAULT_BASE = "/"

export default defineConfig({
  base: process.env["VITE_BASE"] ?? DEFAULT_BASE,
  plugins: [
    curriculumPlugin(CHALLENGES_DIR, INDEX_HTML),
    analyticsPlugin(INDEX_HTML, process.env["VITE_CF_BEACON_TOKEN"]),
    accountCspPlugin([ACCOUNT_HTML, BOARDS_HTML, PLAYER_HTML], API_ORIGIN),
    boardLevelsPlugin(CHALLENGES_DIR, [BOARDS_HTML, PLAYER_HTML]),
    shareCardsPlugin({
      challengesDir: CHALLENGES_DIR,
      imagePath: SHARE_IMAGE,
      pages: {
        [INDEX_HTML]: {
          title: "vimdojo · learn Vim motions by solving puzzles",
          description:
            "Learn Vim motions, Neovim workflows and your own init.lua by solving tiny puzzles in real Neovim, or in your browser. Every key counts: beat par for three stars.",
          url: `${SITE_URL}/`,
        },
        [BOARDS_HTML]: {
          title: "Leaderboards · vimdojo",
          description:
            "Fewest verified keystrokes on today's daily, on each level and across them all, replayed in real Neovim.",
          url: `${SITE_URL}/boards/`,
        },
      },
    }),
  ],
  build: {
    // The lazily loaded demo chunk (CodeMirror + Vim emulation) is ~500 kB
    // minified (~160 kB gzip). It is off the critical path, so allow it.
    chunkSizeWarningLimit: 600,
    rollupOptions: { input: [INDEX_HTML, ACCOUNT_HTML, PRIVACY_HTML, BOARDS_HTML, PLAYER_HTML] },
  },
  server: {
    // challenges/ and tests/fixtures/ live outside web/ and are imported directly,
    // so the data is never copied.
    fs: { allow: [".."] },
  },
  test: {
    projects: [
      {
        extends: true,
        test: {
          name: "unit",
          environment: "jsdom",
          include: ["src/**/*.test.ts", "build/**/*.test.ts"],
          exclude: ["src/**/*.browser.test.ts"],
        },
      },
      {
        // The Vim emulation moves vertically by measuring layout, which jsdom
        // does not implement, so emulation checks run in real Chromium.
        extends: true,
        test: {
          name: "browser",
          include: ["src/**/*.browser.test.ts"],
          browser: {
            enabled: true,
            provider: playwright(),
            headless: true,
            instances: [{ browser: "chromium" }],
          },
        },
      },
    ],
  },
})
