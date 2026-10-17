import "./style.css"

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

const root = document.querySelector<HTMLElement>("#demo")
if (root !== null) {
  root.textContent = "Loading the demo…"
  whenNearViewport(root, () => {
    mountDemo(root).catch((error: unknown) => {
      root.textContent = "The demo failed to load. Try reloading the page."
      console.error(error)
    })
  })
}
