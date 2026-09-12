#!/bin/zsh
# Sign nested Mach-O executables inside bundled MarkItDown with App Sandbox.
# Apple ITMS-90296 rejects python3 / magika / flac-mac without it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-}"
IDENTITY="${2:-}"
ENT="${3:-$ROOT/Resources/YourMark.nested.entitlements}"

if [[ -z "$DEST" || ! -d "$DEST" ]]; then
  echo "usage: sign-nested-python.sh <python-dir> [codesign-identity]" >&2
  exit 1
fi
if [[ ! -f "$ENT" ]]; then
  echo "error: missing $ENT" >&2
  exit 1
fi
if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
  echo "note: skip nested Python sign (no identity)"
  exit 0
fi

is_macho_executable() {
  local info
  info=$(file -b "$1" 2>/dev/null || true)
  [[ "$info" == *Mach-O*executable* ]]
}

echo "note: sandbox-signing nested executables in $DEST"
signed=0
while IFS= read -r -d '' f; do
  if is_macho_executable "$f"; then
    echo "note:   ${f#$DEST/}"
    codesign --force --options runtime --timestamp \
      --entitlements "$ENT" --sign "$IDENTITY" "$f"
    signed=$((signed + 1))
  fi
done < <(find "$DEST" -type f -print0)

echo "note: sandbox-signed $signed nested executable(s)"
