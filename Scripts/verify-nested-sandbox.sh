#!/bin/zsh
# Fail if nested MarkItDown Mach-O is missing App Sandbox (exes) or still adhoc (dylibs).
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
libs=0
exes=0
while IFS= read -r -d '' f; do
  info=$(file -b "$f" 2>/dev/null || true)
  [[ "$info" == *Mach-O* ]] || continue
  sig=$(codesign -dvvv "$f" 2>&1 || true)
  if [[ "$sig" == *adhoc* || "$sig" == *linker-signed* || "$sig" == *"TeamIdentifier=not set"* ]]; then
    echo "error: adhoc/linker-signed (ITMS-90238): ${f#$APP/}" >&2
    fail=1
    continue
  fi
  if [[ "$info" == *executable* && "$info" != *"shared library"* && "$info" != *"bundle"* ]]; then
    ents=$(codesign -d --entitlements - --xml "$f" 2>/dev/null || true)
    if [[ "$ents" != *com.apple.security.app-sandbox* ]]; then
      echo "error: missing App Sandbox: ${f#$APP/}" >&2
      fail=1
    else
      echo "ok exe: ${f#$APP/}"
      exes=$((exes + 1))
    fi
  else
    libs=$((libs + 1))
  fi
done < <(find "$PYTHON" -type f -print0)

if [[ "$fail" -ne 0 ]]; then
  echo "error: nested Python is not ready for App Store" >&2
  exit 1
fi
# Guideline 2.5.1 — Tk 8.6/9.0 embeds this private AppKit name.
hits=$(rg -a -l "_NSWindowDidOrderOnScreenNotification|NSWindowDidOrderOnScreenNotification" "$PYTHON" 2>/dev/null || true)
if [[ -n "$hits" ]]; then
  echo "error: private API string still in:" >&2
  echo "$hits" >&2
  exit 1
fi
if [[ -e "$PYTHON/lib/libtcl9tk9.0.dylib" || -e "$PYTHON/lib/python3.12/lib-dynload/_tkinter.cpython-312-darwin.so" ]]; then
  echo "error: Tcl/Tk is still in the Store Python" >&2
  exit 1
fi
echo "note: no Tk / _NSWindowDidOrderOnScreenNotification in bundled Python"
echo "note: $exes nested executables have App Sandbox; $libs libraries are team-signed"
