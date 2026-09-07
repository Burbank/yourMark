#!/bin/zsh
# Build yourMark.app and wrap it in a drag-to-Applications DMG
# (app beside Applications, arrow on the background).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
chmod +x "$ROOT/Scripts/build-app.sh"

SKIP_INSTALL=1 "$ROOT/Scripts/build-app.sh"

APP="$ROOT/dist/yourMark.app"
STAGE="$ROOT/dist/dmg"
DMG="$ROOT/dist/yourMark.dmg"
RW="$ROOT/dist/yourMark.rw.dmg"
BG="$ROOT/Resources/dmg-background.png"

[[ -d "$APP" ]] || { echo "missing $APP" >&2; exit 1; }
[[ -f "$BG" ]] || { echo "missing $BG" >&2; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE/Support"
cp -R "$APP" "$STAGE/yourMark.app"
cp "$ROOT/Scripts/Privacy & Security Settings.webloc" "$STAGE/Privacy & Security Settings.webloc"
cp "$ROOT/Scripts/Open Privacy & Security Settings.command" "$STAGE/Support/Open Privacy & Security Settings.command"
cp "$ROOT/Scripts/Install yourMark.command" "$STAGE/Support/Install yourMark.command"
cp "$ROOT/Scripts/If macOS blocks yourMark.command" "$STAGE/Support/If macOS blocks yourMark.command"
cp "$ROOT/docs/shots/open-anyway.png" "$STAGE/Support/Open Anyway looks like this.png"
chmod +x "$STAGE/Support/"*.command
cat > "$STAGE/Support/Read me first.txt" <<'TXT'
yourMark
========

Drag yourMark onto Applications (follow the arrow).

If macOS says it "could not verify" yourMark:
  1. Click Done (not Move to Bin)
  2. Double-click "Privacy & Security Settings" on this disk
     (or System Settings → Privacy & Security → Open Anyway)
  or right-click yourMark → Open
  or run "If macOS blocks yourMark" in this Support folder.

First launch downloads Microsoft MarkItDown from PyPI (needs internet
once). The converter is not frozen inside the app, so Microsoft’s
updates still reach you.

Keep the original PDF. Markdown is the working copy.
TXT

rm -f "$DMG" "$RW"

layout_with_create_dmg() {
  command -v create-dmg >/dev/null 2>&1 && return 0
  command -v brew >/dev/null 2>&1 || return 1
  brew install create-dmg >/dev/null
  command -v create-dmg >/dev/null 2>&1
}

if layout_with_create_dmg; then
  # create-dmg adds the Applications drop-link itself.
  create-dmg \
    --volname "yourMark" \
    --background "$BG" \
    --window-pos 200 120 \
    --window-size 660 420 \
    --icon-size 128 \
    --icon "yourMark.app" 165 190 \
    --app-drop-link 495 190 \
    --icon "Privacy & Security Settings.webloc" 165 355 \
    --icon "Support" 495 355 \
    --hide-extension "yourMark.app" \
    --no-internet-enable \
    "$DMG" \
    "$STAGE"
else
  mkdir -p "$STAGE/.background"
  cp "$BG" "$STAGE/.background/background.png"
  ln -sf /Applications "$STAGE/Applications"
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
  if command -v SetFile >/dev/null; then
    SetFile -a V "$VOL/.background" || true
  fi
  osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "yourMark"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 860, 540}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    try
      set background picture of theViewOptions to file ".background:background.png"
    end try
    delay 1
    set position of item "yourMark.app" to {165, 190}
    set position of item "Applications" to {495, 190}
    try
      set position of item "Privacy & Security Settings.webloc" to {165, 355}
    end try
    try
      set position of item "Support" to {495, 355}
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
fi

echo "✓ DMG: $DMG"
