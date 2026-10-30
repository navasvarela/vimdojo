// The account page. Everything from the server is added as text, never as HTML,
// so a handle can't inject markup.
import { h } from "../ui/dom"
import {
  AccountError,
  type AccountApi,
  DELETE_PHRASE,
  type Login,
  type Me,
  SIGN_IN_URL,
} from "./api"

const EXPORT_FILE_NAME = "vimdojo-account.json"
const LOGIN_KIND_LABELS = { web: "Browser", plugin: "Neovim plugin" } as const

function date(iso: string): string {
  return iso.slice(0, 10)
}

export class AccountPage {
  private readonly message = h("p", { className: "demo-message", attrs: { role: "status" } })

  constructor(
    private readonly root: HTMLElement,
    private readonly api: AccountApi,
    private readonly loginFailed: boolean,
  ) {}

  async show(): Promise<void> {
    try {
      const me = await this.api.me()
      if (me === undefined) {
        this.renderSignedOut()
      } else if (me.handle === null) {
        this.renderPickHandle(me)
      } else {
        this.renderAccount(me, me.handle, await this.api.logins())
      }
    } catch (error) {
      this.root.replaceChildren(this.problem(error))
    }
  }

  private problem(error: unknown): HTMLElement {
    const text = error instanceof AccountError ? error.message : "Something went wrong."
    return h("p", { className: "demo-message", attrs: { role: "alert" } }, [text])
  }

  private say(text: string): void {
    this.message.textContent = text
  }

  /** Runs an action, showing a failure instead of losing it, then redraws. */
  private act(action: () => Promise<void>): () => void {
    return () => {
      action()
        .then(() => this.show())
        .catch((error: unknown) => {
          this.say(error instanceof AccountError ? error.message : "Something went wrong.")
        })
    }
  }

  private renderSignedOut(): void {
    this.root.replaceChildren(
      this.loginFailed
        ? h("p", { className: "demo-message", attrs: { role: "alert" } }, [
            "Signing in didn't work. Please try again.",
          ])
        : "",
      h("p", {}, [
        "Accounts are optional: the game works without one. An account is for the leaderboards.",
      ]),
      h("p", { className: "cta" }, [
        h("a", { className: "button primary", attrs: { href: SIGN_IN_URL } }, [
          "Sign in with GitHub",
        ]),
      ]),
      h("p", { className: "aside" }, [
        "vimdojo keeps your GitHub id and the handle you pick, and no email or name. ",
        h("a", { attrs: { href: "/privacy/" } }, ["What's stored"]),
        ".",
      ]),
    )
  }

  private handleForm(me: Me, label: string, submit: string): HTMLFormElement {
    const input = h("input", {
      attrs: { id: "handle", type: "text", required: "", autocomplete: "off", spellcheck: "false" },
    })
    const form = h("form", { className: "account-form" }, [
      h("label", { attrs: { for: "handle" } }, [label]),
      input,
      h("button", { className: "button primary", attrs: { type: "submit" } }, [submit]),
      h("p", { className: "aside" }, [me.handle_rules]),
    ])
    form.addEventListener("submit", (event) => {
      event.preventDefault()
      this.act(() => this.api.setHandle(input.value))()
    })
    return form
  }

  private renderPickHandle(me: Me): void {
    this.root.replaceChildren(
      h("p", {}, ["Pick a public handle. This is your name on the leaderboards."]),
      this.handleForm(me, "Handle", "Save"),
      this.message,
      this.signOutButton(),
    )
  }

  private signOutButton(): HTMLButtonElement {
    const button = h("button", { className: "button", attrs: { type: "button" } }, ["Sign out"])
    button.addEventListener(
      "click",
      this.act(() => this.api.signOut()),
    )
    return button
  }

  private loginRow(login: Login): HTMLElement {
    const label = `${LOGIN_KIND_LABELS[login.kind]}, since ${date(login.created_at)}, last used ${date(login.last_used_at)}`
    if (login.current) {
      return h("li", {}, [`${label} (this one)`])
    }
    const revoke = h("button", { className: "link-button", attrs: { type: "button" } }, ["Revoke"])
    revoke.addEventListener(
      "click",
      this.act(() => this.api.revoke(login.id)),
    )
    return h("li", {}, [`${label} `, revoke])
  }

  private exportButton(): HTMLButtonElement {
    const button = h("button", { className: "button", attrs: { type: "button" } }, [
      "Download my data",
    ])
    button.addEventListener("click", () => {
      this.api
        .exportData()
        .then((text) => {
          const url = URL.createObjectURL(new Blob([text], { type: "application/json" }))
          h("a", { attrs: { href: url, download: EXPORT_FILE_NAME } }).click()
          URL.revokeObjectURL(url)
          this.say(`Downloaded ${EXPORT_FILE_NAME}.`)
        })
        .catch((error: unknown) => {
          this.say(error instanceof AccountError ? error.message : "Something went wrong.")
        })
    })
    return button
  }

  /** Stays disabled until the phrase is typed: deleting can't be undone. */
  private deleteForm(): HTMLFormElement {
    const input = h("input", {
      attrs: { id: "confirm-delete", type: "text", autocomplete: "off", spellcheck: "false" },
    })
    const button = h("button", { className: "button danger", attrs: { type: "submit" } }, [
      "Delete my account",
    ])
    button.disabled = true
    input.addEventListener("input", () => {
      button.disabled = input.value !== DELETE_PHRASE
    })
    const form = h("form", { className: "account-form" }, [
      h("label", { attrs: { for: "confirm-delete" } }, [`Type "${DELETE_PHRASE}" to confirm:`]),
      input,
      button,
    ])
    form.addEventListener("submit", (event) => {
      event.preventDefault()
      if (input.value === DELETE_PHRASE) {
        this.act(() => this.api.deleteAccount())()
      }
    })
    return form
  }

  private renderAccount(me: Me, handle: string, logins: readonly Login[]): void {
    this.root.replaceChildren(
      h("p", {}, ["Signed in as ", h("strong", {}, [handle]), "."]),
      this.message,
      h("h2", {}, ["Change your handle"]),
      this.handleForm(me, "New handle", "Change"),
      h("p", { className: "aside" }, ["A handle can change once every 30 days."]),
      h("h2", {}, ["Your logins"]),
      h(
        "ul",
        { className: "account-logins" },
        logins.map((login) => this.loginRow(login)),
      ),
      h("h2", {}, ["Your data"]),
      h("p", { className: "cta" }, [this.exportButton(), this.signOutButton()]),
      h("h2", {}, ["Delete your account"]),
      h("p", {}, ["This removes your data at once, and can't be undone."]),
      this.deleteForm(),
    )
  }
}
