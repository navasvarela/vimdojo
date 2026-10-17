// Level data uses Neovim's byte columns; CodeMirror uses UTF-16 offsets.
// These convert at the boundary so the rest of the code speaks bytes.

const encoder = new TextEncoder()

export function byteColToIndex(line: string, byteCol: number): number {
  let bytes = 0
  let index = 0
  for (const char of line) {
    if (bytes >= byteCol) {
      break
    }
    bytes += encoder.encode(char).length
    index += char.length
  }
  return index
}

export function indexToByteCol(line: string, index: number): number {
  return encoder.encode(line.slice(0, index)).length
}
