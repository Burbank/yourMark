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
cp "$ROOT/Scripts/Install yourMark.command" "$STAGE/Install yourMark.command"
chmod +x "$STAGE/Install yourMark.command"
cp "$ROOT/Scripts/If macOS blocks yourMark.command" "$STAGE/If macOS blocks yourMark.command"
chmod +x "$STAGE/If macOS blocks yourMark.command"
cat > "$STAGE/Read me first.txt" <<'TXT'
yourMark
========

1. Double-click "Install yourMark".
   That copies the app to Applications, tells macOS it is safe to open,
   and launches it.

2. If macOS says it "could not verify" yourMark and offers Move to Bin:
   click Done (not Move to Bin). Then double-click
   "If macOS blocks yourMark", or:
   • Right-click yourMark → Open
   • System Settings → Privacy & Security → Open Anyway

3. First launch downloads Microsoft MarkItDown from PyPI (needs internet
   once). The converter is not frozen inside the app, so Microsoft’s
   updates still reach you.

Keep the original PDF. Markdown is the working copy.
TXT


rm -f "$DMG"
hdiutil create \
  -volname "yourMark" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG"

echo "✓ DMG: $DMG"
