#!/bin/zsh
# Build yourMark.app and wrap it in a versioned drag-to-Applications DMG.
# Front of the disk: the app and Applications only. No Gatekeeper help files.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
chmod +x "$ROOT/Scripts/build-app.sh"

SKIP_INSTALL=1 "$ROOT/Scripts/build-app.sh"

APP="$ROOT/dist/yourMark.app"
STAGE="$ROOT/dist/dmg"
[[ -d "$APP" ]] || { echo "missing $APP" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "0.0.0")
DMG="$ROOT/dist/yourMark-$VERSION.dmg"
RW="$ROOT/dist/yourMark.rw.dmg"
BG="$ROOT/Resources/dmg-background.png"
swift "$ROOT/Scripts/make-dmg-background.swift" "$BG"

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto --norsrc --noextattr --noqtn "$APP" "$STAGE/yourMark.app"
ln -sf /Applications "$STAGE/Applications"
mkdir -p "$STAGE/.background"
cp "$BG" "$STAGE/.background/background.png"

rm -f "$DMG" "$RW"

hdiutil create \
  -volname "yourMark" \
  -srcfolder "$STAGE" \
  -ov -format UDRW \
  "$RW"

MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW")
DEV=$(echo "$MOUNT" | awk '/^\/dev\/disk/ { print $1; exit }')
VOL="/Volumes/yourMark"
for _ in {1..25}; do
  [[ -d "$VOL/yourMark.app" ]] && break
  sleep 0.4
done

chflags hidden "$VOL/.background" || true
command -v SetFile >/dev/null && SetFile -a V "$VOL/.background" || true

osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "yourMark"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 160, 920, 600}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 192
    set text size of theViewOptions to 14
    try
      set background picture of theViewOptions to file ".background:background.png"
    end try
    delay 1
    set position of item "yourMark.app" to {180, 230}
    set position of item "Applications" to {540, 230}
    try
      set the extension hidden of item "yourMark.app" to true
    end try
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$DEV" || hdiutil detach "$VOL" -force || true
sleep 1
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$RW"

[[ -f "$DMG" ]] || { echo "DMG was not created" >&2; exit 1; }

if [[ -x "$ROOT/Scripts/sign-and-notarize.sh" ]]; then
  "$ROOT/Scripts/sign-and-notarize.sh" "$DMG" || true
fi

echo "✓ DMG: $DMG"
