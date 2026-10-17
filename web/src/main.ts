import "./style.css"
import { mountCopyButtons } from "./landing/copy-buttons"
import { mountHeroDemo } from "./landing/hero-demo"

// The demo (CodeMirror + Vim emulation) is most of the bundle, so it loads
// only when its section approaches the viewport. The landing page stays light.
const PRELOAD_MARGIN = "400px"

async function mountDemo(root: HTMLElement): Promise<void> {
  const [{ demoPacks, loadPacks }, { Demo }, { browserStorage }] = await Promise.all([
    import("./challenges"),
    import("./game/demo"),
    import("./storage"),
  ])
  new Demo(root, demoPacks(loadPacks()), browserStorage())
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
  whenNearViewport(demo, () => {
    mountDemo(demo).catch((error: unknown) => {
      demo.textContent = "The demo failed to load. Try reloading the page."
      console.error(error)
    })
  })
}
