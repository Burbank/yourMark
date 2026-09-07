#!/bin/zsh
# Build yourMark.app and wrap it in a drag-and-drop DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
chmod +x "$ROOT/Scripts/build-app.sh"

SKIP_INSTALL=1 "$ROOT/Scripts/build-app.sh"

APP="$ROOT/dist/yourMark.app"
STAGE="$ROOT/dist/dmg"
DMG="$ROOT/dist/yourMark.dmg"

[[ -d "$APP" ]] || { echo "missing $APP" >&2; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/yourMark.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/Scripts/Install Engine.command" "$STAGE/Install Engine.command" 2>/dev/null || true
chmod +x "$STAGE/Install Engine.command" 2>/dev/null || true

rm -f "$DMG"
hdiutil create \
  -volname "yourMark" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG"

echo "✓ DMG: $DMG"
