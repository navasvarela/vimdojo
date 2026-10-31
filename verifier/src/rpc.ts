// A minimal msgpack-RPC client for one embedded Neovim (`nvim --embed`).
//
// The harness is deliberately an RPC *client* and never a Neovim instance:
// Neovim answers API requests on every channel it has, so if the harness
// were a Neovim, a replayed key log could call `nvim_exec_lua` on it and run
// code as the harness. Requests coming from the child are refused.
import { type ChildProcessWithoutNullStreams, type SpawnOptions, spawn } from "node:child_process"
import { decode, decodeMultiStream, Encoder, ExtensionCodec } from "@msgpack/msgpack"

const MessageType = { Request: 0, Response: 1, Notification: 2 } as const

const REFUSED = "vimdojo verifier: requests from the replayed Neovim are refused"
const EXITED = "Neovim exited"

// Neovim sends Buffer, Window and Tabpage handles as msgpack extension types
// 0, 1 and 2, each wrapping the handle's integer. The API accepts plain
// integers back, so the handles are decoded to numbers.
const NVIM_HANDLE_TYPES = [0, 1, 2]

const extensionCodec = new ExtensionCodec()
for (const type of NVIM_HANDLE_TYPES) {
  extensionCodec.register({ type, encode: () => null, decode: (data) => decode(data) })
}
const encoder = new Encoder({ extensionCodec })

export class NvimError extends Error {}

type Pending = {
  readonly resolve: (value: unknown) => void
  readonly reject: (error: Error) => void
}

function errorMessage(error: unknown): string {
  if (Array.isArray(error) && typeof error[1] === "string") {
    return error[1]
  }
  return String(error)
}

export class NvimClient {
  private nextId = 0
  private exited: boolean = false
  private readonly pending = new Map<number, Pending>()

  private constructor(private readonly child: ChildProcessWithoutNullStreams) {
    // A replayed log can quit Neovim at any moment (`:qa!`), and the next
    // write then fails with EPIPE. Without these handlers that is an uncaught
    // exception: one hostile job would take down the whole batch.
    child.stdin.on("error", () => this.failPending())
    child.on("error", () => this.failPending())
    void this.readLoop()
  }

  /** Starts `nvim --embed --headless` with `args` and attaches to it. */
  static spawn(nvim: string, args: readonly string[], options: SpawnOptions = {}): NvimClient {
    const child = spawn(nvim, ["--embed", "--headless", ...args], { ...options, stdio: "pipe" })
    return new NvimClient(child)
  }

  request(method: string, params: readonly unknown[] = []): Promise<unknown> {
    const id = this.nextId++
    const message = encoder.encode([MessageType.Request, id, method, params])
    return new Promise((resolve, reject) => {
      if (this.exited) {
        reject(new NvimError(EXITED))
        return
      }
      this.pending.set(id, { resolve, reject })
      this.child.stdin.write(message)
    })
  }

  /** Kills the process; pending requests fail. */
  close(): void {
    this.child.kill("SIGKILL")
  }

  private async readLoop(): Promise<void> {
    try {
      for await (const message of decodeMultiStream(this.child.stdout, { extensionCodec })) {
        this.dispatch(message)
      }
    } catch {
      // The stream ends badly when the process is killed; pending requests
      // are failed below either way.
    }
    this.failPending()
  }

  private failPending(): void {
    this.exited = true
    for (const { reject } of this.pending.values()) {
      reject(new NvimError(EXITED))
    }
    this.pending.clear()
  }

  private dispatch(message: unknown): void {
    if (!Array.isArray(message)) {
      return
    }
    const [type, id] = message
    if (type === MessageType.Response && typeof id === "number") {
      const waiter = this.pending.get(id)
      this.pending.delete(id)
      const [, , error, result] = message
      if (error !== null && error !== undefined) {
        waiter?.reject(new NvimError(errorMessage(error)))
      } else {
        waiter?.resolve(result)
      }
    } else if (type === MessageType.Request && typeof id === "number") {
      this.child.stdin.write(encoder.encode([MessageType.Response, id, REFUSED, null]))
    }
    // Notifications are ignored: the replay never relies on the child telling
    // it anything.
  }
}
