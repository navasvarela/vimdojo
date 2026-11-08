import "./style.css"
import { type Challenge, parseChallenge } from "./challenge-link"
import { mountCopyButtons } from "./landing/copy-buttons"
import { mountHeroDemo } from "./landing/hero-demo"

// The demo (CodeMirror + Vim emulation) is most of the bundle, so it loads
// only when its section approaches the viewport. The landing page stays light.
const PRELOAD_MARGIN = "400px"
// The site nav's Daily link and the boards' "play it in your browser" link.
const DAILY_HASH = "#daily"

type DemoHandle = { startDaily(): void }

async function mountDemo(root: HTMLElement, challenge: Challenge | undefined): Promise<DemoHandle> {
  const [{ loadPacks }, { Demo }, { browserStorage }] = await Promise.all([
    import("./challenges"),
    import("./game/demo"),
    import("./storage"),
  ])
  const packs = loadPacks()
  // Looked up in every pack: a challenge can name a level that's only in the plugin.
  const title = packs.flatMap((pack) => pack.levels).find((l) => l.id === challenge?.levelId)?.title
  return new Demo(
    root,
    packs,
    browserStorage(),
    challenge === undefined ? undefined : { challenge, title },
  )
}

function whenNearViewport(element: HTMLElement, callback: () => void): void {
  if (!("IntersectionObserver" in window)) {
    callback()
    return
  }
  const observer = new IntersectionObserver(
    (entries) => {
      if (entries.some((entry) => entry.isIntersecting)) {
        observer.disconnect()
        callback()
      }
    },
    { rootMargin: PRELOAD_MARGIN },
  )
  observer.observe(element)
}

const hero = document.querySelector<HTMLElement>("#hero-demo")
if (hero !== null) {
  mountHeroDemo(hero)
}

mountCopyButtons(document)

const demo = document.querySelector<HTMLElement>("#demo")
if (demo !== null) {
  demo.textContent = "Loading the demo…"
  const challenge = parseChallenge(window.location.search)
  let mounted: Promise<DemoHandle | undefined> | undefined
  const load = (): Promise<DemoHandle | undefined> => {
    mounted ??= mountDemo(demo, challenge).catch((error: unknown) => {
      demo.textContent = "The demo failed to load. Try reloading the page."
      console.error(error)
      return undefined
    })
    return mounted
  }
  const playDaily = async (): Promise<void> => {
    document.querySelector("#play")?.scrollIntoView()
    ;(await load())?.startDaily()
  }
  // A challenge or daily link is someone asking to play: open the demo straight away.
  if (challenge !== undefined) {
    document.querySelector("#play")?.scrollIntoView()
    void load()
  } else if (window.location.hash === DAILY_HASH) {
    void playDaily()
  } else {
    whenNearViewport(demo, () => void load())
  }
  window.addEventListener("hashchange", () => {
    if (window.location.hash === DAILY_HASH) {
      void playDaily()
    }
  })
}
