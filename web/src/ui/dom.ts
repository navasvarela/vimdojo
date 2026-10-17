export type Child = Node | string | null | undefined | false

export type ElementProps = {
  readonly className?: string
  readonly attrs?: Readonly<Record<string, string>>
}

/** Minimal element builder: `h("p", { className: "x" }, ["text", child])`. */
export function h<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  props: ElementProps = {},
  children: readonly Child[] = [],
): HTMLElementTagNameMap[K] {
  const element = document.createElement(tag)
  if (props.className !== undefined) {
    element.className = props.className
  }
  for (const [name, value] of Object.entries(props.attrs ?? {})) {
    element.setAttribute(name, value)
  }
  for (const child of children) {
    if (child !== null && child !== undefined && child !== false) {
      element.append(child)
    }
  }
  return element
}

export function stars(count: number): string {
  return "★".repeat(count) + "☆".repeat(3 - count)
}
