// @vitest-environment node
import { fileURLToPath } from "node:url"
import { describe, expect, it } from "vitest"
import { parsePacks, type Pack } from "../src/challenges"
import { readPacks } from "./curriculum"
import { cardTags, renderSharePages } from "./share-pages"

const CHALLENGES_DIR = fileURLToPath(new URL("../../challenges", import.meta.url))

function pack(level: { id: string; title?: string; web_demo?: boolean }): Pack {
  const [parsed] = parsePacks([
    {
      pack: "x",
      title: "Find & Jump",
      order: 1,
      levels: [
        {
          id: level.id,
          title: level.title ?? "Quotes",
          description: "Delete inside the quotes.",
          start_text: ["a"],
          cursor_start: [1, 0],
          goal: { type: "cursor_at", line: 1, col: 0 },
          par_keys: 3,
          par_seconds: 5,
          hint: "h",
          solution: "l",
          teaches: ["l"],
          ...(level.web_demo === undefined ? {} : { web_demo: level.web_demo }),
        },
      ],
    },
  ])
  if (parsed === undefined) {
    throw new Error("fixture pack didn't parse")
  }
  return parsed
}

describe("share pages", () => {
  it("writes one page per shipped level, at /play/<level>/", () => {
    const packs = readPacks(CHALLENGES_DIR)
    const pages = renderSharePages(packs, "/")
    const levels = packs.flatMap((p) => p.levels)
    expect(pages.map((page) => page.fileName)).toEqual(
      levels.map((level) => `play/${level.id}/index.html`),
    )
  })

  it("names the level, its pack and par in the card, escaped", () => {
    const [page] = renderSharePages([pack({ id: "x-1", title: `"Quotes" <&>` })], "/")
    expect(page?.html).toContain(
      `<meta property="og:title" content="&quot;&quot;Quotes&quot; &lt;&amp;&gt;&quot; · vimdojo" />`,
    )
    expect(page?.html).toContain("A Find &amp; Jump level, par 3 keys. Delete inside the quotes.")
    expect(page?.html).toContain(
      `<meta property="og:url" content="https://vimdojo.org/play/x-1/" />`,
    )
  })

  it.each([
    [true, "Play it in your browser"],
    [false, "It's a level in the Neovim plugin"],
  ])("says where a level with web_demo %s can be played", (webDemo, text) => {
    const [page] = renderSharePages([pack({ id: "x-1", web_demo: webDemo })], "/")
    expect(page?.html).toContain(text)
  })

  it("forwards to the demo with the count, under the site's base", () => {
    const [page] = renderSharePages([pack({ id: "x-1" })], "/vimdojo/")
    expect(page?.html).toContain(`const query = "?play=x-1"`)
    expect(page?.html).toContain(`location.replace("/vimdojo/" + query)`)
    expect(page?.html).toContain(`<a href="/vimdojo/?play=x-1">`)
  })

  it("refuses a level id that isn't safe in a path or a script", () => {
    expect(() => renderSharePages([pack({ id: `x"); alert(1); ("` })], "/")).toThrow(
      "can't be a share page path",
    )
  })
})

describe("card tags", () => {
  it("point at the absolute image and ask for a large card", () => {
    const tags = cardTags({ title: "t", description: "d", url: "https://vimdojo.org/" })
    expect(tags).toContain(`<meta property="og:image" content="https://vimdojo.org/og.png" />`)
    expect(tags).toContain(`<meta name="twitter:card" content="summary_large_image" />`)
  })
})
