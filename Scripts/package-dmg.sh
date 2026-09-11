#!/bin/zsh
# Classic Mac installer disk: HFS+, PNG background baked into .DS_Store, two large icons.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
chmod +x "$ROOT/Scripts/build-app.sh"

SKIP_INSTALL=1 "$ROOT/Scripts/build-app.sh"

APP="$ROOT/dist/yourMark.app"
[[ -d "$APP" ]] || { echo "missing $APP" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "0.0.0")
DMG="$ROOT/dist/yourMark-$VERSION.dmg"
BG="$ROOT/Resources/dmg-background.png"
swift "$ROOT/Scripts/make-dmg-background.swift" "$BG"

VENV="${YOURMARK_DMG_VENV:-/tmp/yourmark-dmgvenv}"
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q dmgbuild
fi

# Drop leftover mounts so Finder does not reuse an old yourMark window.
setopt NULL_GLOB
for vol in /Volumes/yourMark /Volumes/yourMark\ * /Volumes/yourMark\ 1; do
  [[ -d "$vol" ]] && hdiutil detach "$vol" -force >/dev/null 2>&1 || true
done
unsetopt NULL_GLOB

rm -f "$DMG"
export YOURMARK_DMG_ROOT="$ROOT"
export YOURMARK_DMG_APP="$APP"
export YOURMARK_DMG_BG="$BG"
export YOURMARK_DMG_OUT="$DMG"
"$VENV/bin/dmgbuild" -s "$ROOT/Scripts/dmg-settings.py" "yourMark" "$DMG"

[[ -f "$DMG" ]] || { echo "DMG was not created" >&2; exit 1; }

if [[ -x "$ROOT/Scripts/sign-and-notarize.sh" ]]; then
  "$ROOT/Scripts/sign-and-notarize.sh" "$DMG" || true
fi

echo "✓ DMG: $DMG"
