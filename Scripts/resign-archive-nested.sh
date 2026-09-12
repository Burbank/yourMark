#!/bin/zsh
# Re-apply App Sandbox on nested Python executables inside an .app or .xcarchive.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "usage: resign-archive-nested.sh <yourMark.app|yourMark.xcarchive>" >&2
  exit 1
fi

APP="$TARGET"
if [[ "$TARGET" == *.xcarchive ]]; then
  APP="$TARGET/Products/Applications/yourMark.app"
fi
if [[ ! -d "$APP/Contents/Resources/python" ]]; then
  echo "error: no bundled Python in $APP" >&2
  exit 1
fi

IDENTITY="${2:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Apple \(Distribution\|Development\).*\)/\1/p' | head -1)
fi
if [[ -z "$IDENTITY" ]]; then
  echo "error: could not read signing identity from $APP" >&2
  exit 1
fi

echo "note: re-signing nested Python as $IDENTITY"
chmod +x "$ROOT/Scripts/sign-nested-python.sh"
"$ROOT/Scripts/sign-nested-python.sh" "$APP/Contents/Resources/python" "$IDENTITY"

# Outer app must be signed after its contents change. Do not --deep.
APP_ENT="$ROOT/Resources/YourMark.mas.entitlements"
if [[ -f "$APP_ENT" ]]; then
  codesign --force --options runtime --timestamp \
    --entitlements "$APP_ENT" --sign "$IDENTITY" "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
echo "note: re-signed $APP"
