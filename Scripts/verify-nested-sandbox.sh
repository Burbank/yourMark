#!/bin/zsh
# Fail if nested MarkItDown executables lack App Sandbox (ITMS-90296).
set -euo pipefail

APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "usage: verify-nested-sandbox.sh <yourMark.app>" >&2
  exit 1
fi

PYTHON="$APP/Contents/Resources/python"
if [[ ! -d "$PYTHON" ]]; then
  echo "error: no bundled Python at $PYTHON" >&2
  exit 1
fi

fail=0
while IFS= read -r -d '' f; do
  info=$(file -b "$f" 2>/dev/null || true)
  [[ "$info" == *Mach-O*executable* ]] || continue
  ents=$(codesign -d --entitlements - --xml "$f" 2>/dev/null || true)
  if [[ "$ents" != *com.apple.security.app-sandbox* ]]; then
    echo "error: missing App Sandbox: ${f#$APP/}" >&2
    fail=1
  else
    echo "ok: ${f#$APP/}"
  fi
done < <(find "$PYTHON" -type f -print0)

if [[ "$fail" -ne 0 ]]; then
  echo "error: nested executables are missing App Sandbox (ITMS-90296)" >&2
  exit 1
fi
echo "note: nested Python executables have App Sandbox"
