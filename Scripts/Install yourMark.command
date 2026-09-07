#!/bin/zsh
# Double-click this. Copies yourMark to Applications, clears the
# macOS quarantine flag, and opens the app.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC=""
if [[ -d "$HERE/yourMark.app" ]]; then
  SRC="$HERE/yourMark.app"
fi
DEST="/Applications/yourMark.app"

osascript <<'APPLESCRIPT'
display dialog "yourMark will be copied to Applications and opened.

If macOS later says it “could not verify” the app and offers Move to Bin:
• Click Done — not Move to Bin
• Then System Settings → Privacy & Security → Open Anyway
  or right-click yourMark → Open

First launch downloads Microsoft MarkItDown (official PyPI package). That needs the internet once." buttons {"Install"} default button 1 with title "Install yourMark"
APPLESCRIPT

if [[ -n "$SRC" ]]; then
  osascript -e 'tell application "yourMark" to quit' >/dev/null 2>&1 || true
  sleep 0.3
  rm -rf "$DEST"
  cp -R "$SRC" "$DEST"
fi

if [[ ! -d "$DEST" ]]; then
  osascript -e 'display dialog "Could not find yourMark.app. Keep this file next to the app on the disk image, or drag yourMark into Applications first." buttons {"OK"} default button 1 with title "yourMark"'
  exit 1
fi

xattr -cr "$DEST" >/dev/null 2>&1 || true
open "$DEST"
