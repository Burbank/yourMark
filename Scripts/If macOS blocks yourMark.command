#!/bin/zsh
# Double-click this if macOS says yourMark cannot be opened.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP=""
if [[ -d "$HERE/yourMark.app" ]]; then
  APP="$HERE/yourMark.app"
elif [[ -d "/Applications/yourMark.app" ]]; then
  APP="/Applications/yourMark.app"
fi
if [[ -z "$APP" ]]; then
  osascript -e 'display dialog "Could not find yourMark.app. Drag it into Applications first, then click this again." buttons {"OK"} default button 1'
  exit 1
fi
xattr -cr "$APP" >/dev/null 2>&1 || true
open "$APP"
osascript <<'APPLESCRIPT'
display dialog "yourMark is opened.

Apple has not notarized this build yet, so macOS warns once.

If it still will not launch:
1. Right-click yourMark → Open
2. Or System Settings → Privacy & Security → Open Anyway

Then the app installs Microsoft MarkItDown by itself (one download from PyPI)." buttons {"OK"} default button 1 with title "yourMark"
APPLESCRIPT
