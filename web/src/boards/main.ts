import "../style.css"
import { BoardsApi } from "./api"
import { boardUrl, showBoard } from "./pages"

const root = document.querySelector<HTMLElement>("#board")
const picker = document.querySelector<HTMLSelectElement>("#level")
if (root !== null && picker !== null) {
  const api = new BoardsApi()
  const asked = new URLSearchParams(window.location.search).get("level")
  // The picker only lists ranked levels, so an unknown one falls back to the first.
  if (asked !== null && [...picker.options].some((option) => option.value === asked)) {
    picker.value = asked
  }
  picker.addEventListener("change", () => {
    window.history.replaceState(null, "", boardUrl(picker.value))
    void showBoard(root, api, picker.value)
  })
  void showBoard(root, api, picker.value)
}
