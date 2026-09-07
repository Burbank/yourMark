#!/bin/zsh
# If Apple says it could not verify yourMark — click Done, then this.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP=""
if [[ -d "/Applications/yourMark.app" ]]; then
  APP="/Applications/yourMark.app"
elif [[ -d "$HERE/yourMark.app" ]]; then
  APP="$HERE/yourMark.app"
fi
if [[ -z "$APP" ]]; then
  osascript -e 'display dialog "Could not find yourMark.app. Double-click “Install yourMark” first." buttons {"OK"} default button 1 with title "yourMark"'
  exit 1
fi
xattr -cr "$APP" >/dev/null 2>&1 || true
open "$APP"
osascript <<'APPLESCRIPT'
display dialog "Quarantine flag cleared and yourMark opened.

Apple has not notarized this build yet, so macOS warns once. That is expected.

If it still will not launch:
1. Click Done on the warning — not Move to Bin
2. Right-click yourMark → Open
3. Or System Settings → Privacy & Security → Open Anyway

Then the app installs Microsoft MarkItDown by itself (one download from PyPI)." buttons {"OK"} default button 1 with title "yourMark"
APPLESCRIPT
