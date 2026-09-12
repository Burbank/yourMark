#!/bin/zsh
# Build a Mac App Store flavor of yourMark.app (sandboxed, no PyPI installs).
# productbuild needs a "3rd Party Mac Developer Installer" identity to submit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
chmod +x "$ROOT/Scripts/build-app.sh"

ENGINE="$ROOT/Resources/BundledEngine"
if [[ ! -x "$ENGINE/bin/python3" && ! -x "$ENGINE/bin/python3.12" ]]; then
  echo "→ Bundled Microsoft MarkItDown is missing — building it once…"
  chmod +x "$ROOT/Scripts/bundle-engine.sh"
  "$ROOT/Scripts/bundle-engine.sh" "$ENGINE"
fi

DISTRIBUTION=mas SKIP_INSTALL=1 "$ROOT/Scripts/build-app.sh"

APP="$ROOT/dist/yourMark.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
PKG="$ROOT/dist/yourMark-$VERSION-mas.pkg"

IDENTITY="${MAS_INSTALLER_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/3rd Party Mac Developer Installer|Mac Installer/{print $2; exit}')
fi

rm -f "$PKG"
if [[ -n "$IDENTITY" ]]; then
  echo "→ productbuild as $IDENTITY…"
  productbuild --component "$APP" /Applications --sign "$IDENTITY" "$PKG"
else
  echo "→ productbuild (unsigned pkg — import a Mac Installer cert to submit)…"
  productbuild --component "$APP" /Applications "$PKG"
fi

echo "✓ MAS package: $PKG"
echo "Next: upload in Transporter / App Store Connect. See docs/apple-distribution.md"
