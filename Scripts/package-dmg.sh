#!/bin/zsh
# Build yourMark.app and wrap it in a versioned drag-to-Applications DMG.
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
LATEST="$ROOT/dist/yourMark.dmg"
RW="$ROOT/dist/yourMark.rw.dmg"
BG="$ROOT/Resources/dmg-background.png"
[[ -f "$BG" ]] || { echo "missing $BG" >&2; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE/Support"
cp -R "$APP" "$STAGE/yourMark.app"
# Do not put .command files on the disk. Gatekeeper treats them as unsigned
# programs and shows “Move to Bin” — the same scare as the app itself.
# Do not use a .webloc to GitHub Pages either — that 404s if Pages is off.
# A local HTML file opens in Safari from this disk. No internet needed.
cp "$ROOT/Resources/If Apple blocks it.html" "$STAGE/If Apple blocks it.html"
cp "$ROOT/Resources/Open Anyway.html" "$STAGE/Support/Open Anyway.html"
if [[ -f "$ROOT/docs/shots/open-anyway.png" ]]; then
  cp "$ROOT/docs/shots/open-anyway.png" "$STAGE/Support/Open Anyway looks like this.png"
fi
cat > "$STAGE/Support/Read me first.txt" <<TXT
yourMark $VERSION
================

1. Drag yourMark onto Applications (follow the arrow).
2. If macOS blocks it: click Done (not Move to Bin).
3. Open “If Apple blocks it” on this disk — that is a help page in Safari,
   not a program. Safari may ask to open System Settings. Click Allow,
   then Open Anyway.

You can also right-click yourMark → Open.

First launch installs Microsoft MarkItDown from PyPI (internet once).
Keep the original PDF. Markdown is the working copy.
TXT

rm -f "$DMG" "$LATEST" "$RW"

make_plain() {
  ln -sf /Applications "$STAGE/Applications"
  hdiutil create \
    -volname "yourMark $VERSION" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG"
}

layout_osascript() {
  mkdir -p "$STAGE/.background"
  cp "$BG" "$STAGE/.background/background.png"
  [[ -L "$STAGE/Applications" ]] || ln -sf /Applications "$STAGE/Applications"
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
  command -v SetFile >/dev/null && SetFile -a V "$VOL/.background" || true
  osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "yourMark"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 860, 660}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    try
      set background picture of theViewOptions to file ".background:background.png"
    end try
    delay 1
    set position of item "yourMark.app" to {165, 175}
    set position of item "Applications" to {495, 175}
    try
      set position of item "If Apple blocks it.html" to {165, 365}
    end try
    try
      set position of item "Support" to {495, 365}
    end try
    try
      set the extension hidden of item "If Apple blocks it.html" to true
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
}

if command -v create-dmg >/dev/null 2>&1 || (command -v brew >/dev/null 2>&1 && brew install create-dmg); then
  if create-dmg \
      --volname "yourMark $VERSION" \
      --background "$BG" \
      --window-pos 200 120 \
      --window-size 660 540 \
      --icon-size 128 \
      --icon "yourMark.app" 165 175 \
      --app-drop-link 495 175 \
      --icon "If Apple blocks it.html" 165 365 \
      --icon "Support" 495 365 \
      --hide-extension "yourMark.app" \
      --hide-extension "If Apple blocks it.html" \
      --no-internet-enable \
      "$DMG" \
      "$STAGE"; then
    :
  else
    echo "create-dmg failed — trying Finder layout" >&2
    layout_osascript || make_plain
  fi
else
  layout_osascript || make_plain
fi

[[ -f "$DMG" ]] || { echo "DMG was not created" >&2; exit 1; }
cp -f "$DMG" "$LATEST"
echo "✓ DMG: $DMG"
echo "✓ also: $LATEST"
