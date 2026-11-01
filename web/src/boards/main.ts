import "../style.css"
import { BoardsApi } from "./api"
import { boardUrl, showBoard, showDaily } from "./pages"

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

  const dailyRoot = document.querySelector<HTMLElement>("#daily")
  if (dailyRoot !== null) {
    // Only a date goes in the API's path. The API decides whether that day exists.
    const dailyParam = new URLSearchParams(window.location.search).get("daily")
    void showDaily(dailyRoot, api, {
      date: dailyParam !== null && /^\d{4}-\d{2}-\d{2}$/.test(dailyParam) ? dailyParam : undefined,
      now: Date.now(),
      levelNames: new Map([...picker.options].map((option) => [option.value, option.text])),
    })
  }
}
