#!/usr/bin/env bash
# Lints .github/workflows with actionlint, downloading a pinned release into
# .deps/ on first use. The SHA-256 of each archive is pinned here (copied from
# the release's actionlint_<version>_checksums.txt), so a replaced download
# fails instead of running. To upgrade, change VERSION and every hash.
set -euo pipefail

VERSION=1.7.12
# A function rather than an associative array: macOS ships bash 3.2.
pinned_sha256() {
  case "$1" in
    darwin_amd64) echo 5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644 ;;
    darwin_arm64) echo aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f ;;
    linux_amd64) echo 8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8 ;;
    linux_arm64) echo 325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6 ;;
  esac
}

root=$(cd "$(dirname "$0")/.." && pwd)
dir="$root/.deps/actionlint-$VERSION"
bin="$dir/actionlint"

if [[ ! -x "$bin" ]]; then
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)
  case "$arch" in
    x86_64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
  esac
  platform="${os}_${arch}"
  expected=$(pinned_sha256 "$platform")
  if [[ -z "$expected" ]]; then
    echo "actionlint: no pinned build for $platform" >&2
    exit 1
  fi
  archive="actionlint_${VERSION}_${platform}.tar.gz"
  mkdir -p "$dir"
  curl -fsSL -o "$dir/$archive" \
    "https://github.com/rhysd/actionlint/releases/download/v${VERSION}/${archive}"
  actual=$( (command -v sha256sum >/dev/null && sha256sum "$dir/$archive" || shasum -a 256 "$dir/$archive") | cut -d' ' -f1)
  if [[ "$actual" != "$expected" ]]; then
    rm -f "$dir/$archive"
    echo "actionlint: checksum mismatch for $archive" >&2
    exit 1
  fi
  tar -xzf "$dir/$archive" -C "$dir" actionlint
  rm -f "$dir/$archive"
fi

cd "$root"
exec "$bin" "$@"
