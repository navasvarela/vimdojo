import { fileURLToPath } from "node:url"
import { playwright } from "@vitest/browser-playwright"
import { defineConfig } from "vitest/config"
import { analyticsPlugin } from "./build/analytics"
import { curriculumPlugin } from "./build/curriculum"

const CHALLENGES_DIR = fileURLToPath(new URL("../challenges", import.meta.url))
const INDEX_HTML = fileURLToPath(new URL("index.html", import.meta.url))

// The site is served from the root of its custom domain (vimdojo.org).
// Set VITE_BASE=/<repo-name>/ to serve it from a github.io project page instead.
const DEFAULT_BASE = "/"

export default defineConfig({
  base: process.env["VITE_BASE"] ?? DEFAULT_BASE,
  plugins: [
    curriculumPlugin(CHALLENGES_DIR, INDEX_HTML),
    analyticsPlugin(INDEX_HTML, process.env["VITE_CF_BEACON_TOKEN"]),
  ],
  build: {
    // The lazily loaded demo chunk (CodeMirror + Vim emulation) is ~500 kB
    // minified (~160 kB gzip). It is off the critical path, so allow it.
    chunkSizeWarningLimit: 600,
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
