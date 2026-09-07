#!/bin/zsh
# If Apple says it could not verify yourMark — click Done, then this.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

# Jump straight to Privacy & Security (Open Anyway).
open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension" 2>/dev/null \
  || open "x-apple.systempreferences:com.apple.preference.security" 2>/dev/null \
  || open /System/Library/PreferencePanes/Security.prefPane 2>/dev/null \
  || true

APP=""
if [[ -d "/Applications/yourMark.app" ]]; then
  APP="/Applications/yourMark.app"
elif [[ -d "$HERE/../yourMark.app" ]]; then
  APP="$HERE/../yourMark.app"
elif [[ -d "$HERE/yourMark.app" ]]; then
  APP="$HERE/yourMark.app"
fi
if [[ -n "$APP" ]]; then
  xattr -cr "$APP" >/dev/null 2>&1 || true
fi

osascript <<'APPLESCRIPT'
display dialog "System Settings → Privacy & Security is open.

Scroll to Security. After macOS blocked yourMark, click Open Anyway.

That remembers this copy of the app. Apple does not offer “Always Trust this developer” until the build is signed and notarized.

Click Done on the warning — not Move to Bin." buttons {"OK"} default button 1 with title "yourMark"
APPLESCRIPT
