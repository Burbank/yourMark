#!/bin/zsh
# Sign the DMG with Developer ID and staple a notarization ticket.
# No-op when credentials are missing (local ad-hoc builds stay unsigned by Apple).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="${1:-}"
if [[ -z "$DMG" ]]; then
  DMG=$(ls -1t "$ROOT"/dist/yourMark-*.dmg 2>/dev/null | head -1 || true)
fi
[[ -n "$DMG" && -f "$DMG" ]] || { echo "No DMG to notarize" >&2; exit 1; }

IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')
fi
if [[ -z "$IDENTITY" ]]; then
  echo "Skipping notarization — no Developer ID Application identity"
  exit 0
fi

echo "→ Signing DMG as $IDENTITY…"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

PROFILE="${NOTARY_PROFILE:-yourmark-notary}"
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "→ Submitting to notarytool (keychain profile $PROFILE)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
elif [[ -n "${APPLE_API_KEY:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER:-}" ]]; then
  echo "→ Submitting to notarytool (App Store Connect API key)…"
  xcrun notarytool submit "$DMG" \
    --key "$APPLE_API_KEY" \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER" \
    --wait
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  echo "→ Submitting to notarytool (Apple ID)…"
  xcrun notarytool submit "$DMG" \
    --apple-id "$APPLE_ID" \
    --team-id "${APPLE_TEAM_ID:-R4SB7G9A32}" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
else
  echo "DMG is Developer ID–signed. Add notary credentials to staple a ticket."
  echo "See docs/apple-distribution.md"
  exit 0
fi

echo "→ Stapling…"
xcrun stapler staple "$DMG"
echo "✓ Notarized: $DMG"
