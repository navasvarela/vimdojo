import "../style.css"
import { BoardsApi } from "./api"
import { showPlayer } from "./pages"

const root = document.querySelector<HTMLElement>("#player")
const heading = document.querySelector<HTMLElement>("#player-name")
const levels = document.querySelector<HTMLSelectElement>("#level")
if (root !== null && heading !== null && levels !== null) {
  const names = new Map([...levels.options].map((option) => [option.value, option.text]))
  const handle = new URLSearchParams(window.location.search).get("handle")
  void showPlayer(root, heading, new BoardsApi(), handle, names)
}
