#!/bin/zsh
# Sign every nested Mach-O inside bundled MarkItDown.
# Executables get App Sandbox + inherit (ITMS-90296).
# dylibs / .so must also be team-signed or Apple rejects ITMS-90238
# (adhoc linker-signed: valid on disk, does not satisfy designated Requirement).
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

is_macho() {
  local info="$1"
  [[ "$info" == *Mach-O* ]]
}

is_macho_executable() {
  local info="$1"
  [[ "$info" == *executable* && "$info" != *"shared library"* && "$info" != *"bundle"* ]]
}

echo "note: signing nested Mach-O in $DEST"
exe=0
lib=0
# Deepest first so dependents are signed after their libraries.
while IFS= read -r f; do
  info=$(file -b "$f" 2>/dev/null || true)
  is_macho "$info" || continue
  codesign --remove-signature "$f" 2>/dev/null || true
  if is_macho_executable "$info"; then
    codesign --force --options runtime --timestamp \
      --entitlements "$ENT" --sign "$IDENTITY" "$f"
    exe=$((exe + 1))
  else
    codesign --force --options runtime --timestamp \
      --sign "$IDENTITY" "$f"
    lib=$((lib + 1))
  fi
done < <(find "$DEST" -type f | LC_ALL=C sort -r)

echo "note: signed $exe nested executable(s) and $lib nested library/bundle(s)"
