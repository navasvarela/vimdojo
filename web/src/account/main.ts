import "../style.css"
import { AccountApi } from "./api"
import { AccountPage } from "./page"

const root = document.querySelector<HTMLElement>("#account")
if (root !== null) {
  const loginFailed = new URLSearchParams(window.location.search).get("login") === "failed"
  void new AccountPage(root, new AccountApi(), loginFailed).show()
}
