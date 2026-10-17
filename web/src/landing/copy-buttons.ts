// Adds a "Copy" button to every <pre data-copy> block.

const COPIED_RESET_MS = 1600

async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text)
    return true
  } catch {
    return false
  }
}

function selectContents(element: HTMLElement): void {
  const range = document.createRange()
  range.selectNodeContents(element)
  const selection = window.getSelection()
  selection?.removeAllRanges()
  selection?.addRange(range)
}

export function mountCopyButtons(root: ParentNode): void {
  for (const block of root.querySelectorAll<HTMLElement>("pre[data-copy]")) {
    const code = block.querySelector("code") ?? block
    const button = document.createElement("button")
    button.type = "button"
    button.className = "copy-button"
    button.textContent = "Copy"
    button.setAttribute("aria-label", `Copy ${block.dataset["copy"] ?? "snippet"}`)
    button.addEventListener("click", () => {
      void copyText(code.textContent ?? "").then((copied) => {
        if (!copied) {
          // Clipboard API unavailable (insecure context, permissions): select
          // the text so a manual copy is one keystroke away.
          selectContents(code)
        }
        button.textContent = copied ? "Copied" : "Selected"
        window.setTimeout(() => (button.textContent = "Copy"), COPIED_RESET_MS)
      })
    })
    // The button lives beside the <pre>, not inside it, so it stays put when
    // a long snippet scrolls horizontally.
    const wrapper = document.createElement("div")
    wrapper.className = "snippet"
    block.replaceWith(wrapper)
    wrapper.append(block, button)
  }
}
