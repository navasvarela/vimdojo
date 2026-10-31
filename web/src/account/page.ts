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

function statusLine(): HTMLElement {
  return h("p", { className: "account-status", attrs: { role: "status" } })
}

function problemText(error: unknown): string {
  return error instanceof AccountError ? error.message : "Something went wrong."
}

export class AccountPage {
  /** Says what just happened, across the redraw that follows a change. */
  private notice = ""

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
      this.root.replaceChildren(
        h("p", { className: "demo-message", attrs: { role: "alert" } }, [problemText(error)]),
      )
    }
  }

  /**
   * Runs an action from a control, then redraws. A failure shows in `status`,
   * which sits next to that control, so it can't happen out of view. The control
   * is disabled meanwhile, so a slow request still visibly did something.
   */
  private act(
    control: HTMLButtonElement,
    status: HTMLElement,
    action: () => Promise<void>,
    notice = "",
  ): void {
    control.disabled = true
    status.textContent = ""
    action()
      .then(() => {
        this.notice = notice
        return this.show()
      })
      .catch((error: unknown) => {
        control.disabled = false
        status.textContent = problemText(error)
      })
  }

  private takeNotice(): HTMLElement | "" {
    const notice = this.notice
    this.notice = ""
    return notice === ""
      ? ""
      : h("p", { className: "account-status", attrs: { role: "status" } }, [notice])
  }

  private renderSignedOut(): void {
    this.root.replaceChildren(
      this.takeNotice(),
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
      className: "account-input",
      attrs: { id: "handle", type: "text", required: "", autocomplete: "off", spellcheck: "false" },
    })
    const button = h("button", { className: "button primary", attrs: { type: "submit" } }, [submit])
    const status = statusLine()
    const form = h("form", { className: "account-form" }, [
      h("label", { className: "account-label", attrs: { for: "handle" } }, [label]),
      input,
      button,
      h("p", { className: "aside account-note" }, [me.handle_rules]),
      status,
    ])
    form.addEventListener("submit", (event) => {
      event.preventDefault()
      const handle = input.value
      this.act(button, status, () => this.api.setHandle(handle), `Your handle is now ${handle}.`)
    })
    return form
  }

  private renderPickHandle(me: Me): void {
    const status = statusLine()
    this.root.replaceChildren(
      this.takeNotice(),
      h("p", {}, ["Pick a public handle. This is your name on the leaderboards."]),
      this.handleForm(me, "Handle", "Save"),
      this.signOutButton(status),
      status,
    )
  }

  private signOutButton(status: HTMLElement): HTMLButtonElement {
    const button = h("button", { className: "button", attrs: { type: "button" } }, ["Sign out"])
    button.addEventListener("click", () => {
      this.act(button, status, () => this.api.signOut(), "You're signed out.")
    })
    return button
  }

  private loginRow(login: Login): HTMLElement {
    const label = `${LOGIN_KIND_LABELS[login.kind]}, since ${date(login.created_at)}, last used ${date(login.last_used_at)}`
    if (login.current) {
      return h("li", {}, [`${label} (this one)`])
    }
    const revoke = h("button", { className: "link-button", attrs: { type: "button" } }, ["Revoke"])
    const status = statusLine()
    revoke.addEventListener("click", () => {
      this.act(revoke, status, () => this.api.revoke(login.id), "That login is revoked.")
    })
    return h("li", {}, [`${label} `, revoke, status])
  }

  private exportButton(status: HTMLElement): HTMLButtonElement {
    const button = h("button", { className: "button", attrs: { type: "button" } }, [
      "Download my data",
    ])
    button.addEventListener("click", () => {
      status.textContent = ""
      this.api
        .exportData()
        .then((text) => {
          const url = URL.createObjectURL(new Blob([text], { type: "application/json" }))
          h("a", { attrs: { href: url, download: EXPORT_FILE_NAME } }).click()
          URL.revokeObjectURL(url)
          status.textContent = `Downloaded ${EXPORT_FILE_NAME}.`
        })
        .catch((error: unknown) => {
          status.textContent = problemText(error)
        })
    })
    return button
  }

  /** Stays disabled until the phrase is typed: deleting can't be undone. */
  private deleteForm(): HTMLFormElement {
    const input = h("input", {
      className: "account-input",
      attrs: { id: "confirm-delete", type: "text", autocomplete: "off", spellcheck: "false" },
    })
    const button = h("button", { className: "button danger", attrs: { type: "submit" } }, [
      "Delete my account",
    ])
    button.disabled = true
    input.addEventListener("input", () => {
      button.disabled = input.value !== DELETE_PHRASE
    })
    const status = statusLine()
    const form = h("form", { className: "account-form" }, [
      h("label", { className: "account-label", attrs: { for: "confirm-delete" } }, [
        `Type "${DELETE_PHRASE}" to confirm:`,
      ]),
      input,
      button,
      status,
    ])
    form.addEventListener("submit", (event) => {
      event.preventDefault()
      if (input.value === DELETE_PHRASE) {
        this.act(button, status, () => this.api.deleteAccount(), "Your account is deleted.")
      }
    })
    return form
  }

  /** During the cooldown there's nothing to submit, so say when instead of offering a form. */
  private changeHandle(me: Me): Array<HTMLElement> {
    if (me.handle_changes_at !== null) {
      return [
        h("p", {}, [
          `A handle can change once every 30 days. You can change yours again on ${date(me.handle_changes_at)}.`,
        ]),
      ]
    }
    return [
      this.handleForm(me, "New handle", "Change"),
      h("p", { className: "aside" }, ["A handle can change once every 30 days."]),
    ]
  }

  private renderAccount(me: Me, handle: string, logins: readonly Login[]): void {
    const dataStatus = statusLine()
    this.root.replaceChildren(
      this.takeNotice(),
      h("p", {}, ["Signed in as ", h("strong", {}, [handle]), "."]),
      h("h2", {}, ["Change your handle"]),
      ...this.changeHandle(me),
      h("h2", {}, ["Your logins"]),
      h(
        "ul",
        { className: "account-logins" },
        logins.map((login) => this.loginRow(login)),
      ),
      h("h2", {}, ["Your data"]),
      h("p", { className: "cta" }, [this.exportButton(dataStatus), this.signOutButton(dataStatus)]),
      dataStatus,
      h("h2", {}, ["Delete your account"]),
      h("p", {}, ["This removes your data at once, and can't be undone."]),
      this.deleteForm(),
    )
  }
}
