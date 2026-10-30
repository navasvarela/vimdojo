// @vitest-environment node
import { describe, expect, it } from "vitest"
import { injectBeacon } from "./analytics"

const PAGE = "<html><body><main></main>\n  </body></html>"

describe("analytics beacon", () => {
  it.each([
    ["no token", undefined],
    ["an empty token", ""],
  ])("leaves the page untouched with %s", (_, token) => {
    expect(injectBeacon(PAGE, token)).toBe(PAGE)
  })

  it("adds the beacon with the token at the end of the body", () => {
    const html = injectBeacon(PAGE, "abc123")
    expect(html).toContain(
      '<script type="module" src="https://static.cloudflareinsights.com/beacon.min.js" data-cf-beacon="{&quot;token&quot;:&quot;abc123&quot;}"></script>',
    )
    expect(html.indexOf("beacon.min.js")).toBeLessThan(html.indexOf("</body>"))
    expect(html.indexOf("</main>")).toBeLessThan(html.indexOf("beacon.min.js"))
  })

  it("escapes a token that would break out of the JSON or the attribute", () => {
    const html = injectBeacon(PAGE, `a"><script>x</script>\\`)
    expect(html).not.toContain("<script>x")
    expect(html).toContain("{&quot;token&quot;:&quot;a\\&quot;&gt;&lt;script&gt;x&lt;/script&gt;\\\\&quot;}")
  })

  it("rejects a page without a closing body tag when a token is set", () => {
    expect(() => injectBeacon("<main></main>", "abc123")).toThrow("</body>")
  })
})
