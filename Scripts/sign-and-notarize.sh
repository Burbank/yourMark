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
  if [[ "${REQUIRE_NOTARIZATION:-}" == "1" ]]; then
    echo "No Developer ID Application identity. Notarization cannot run." >&2
    exit 1
  fi
  echo "Skipping notarization — no Developer ID Application identity"
  exit 0
fi

echo "→ Signing DMG as $IDENTITY…"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

submit_dmg() {
  local how="$1"
  shift
  echo "→ Submitting to notarytool ($how)…"
  if ! xcrun notarytool submit "$DMG" "$@" --wait; then
    echo "notarytool rejected the DMG." >&2
    exit 1
  fi
}

PROFILE="${NOTARY_PROFILE:-yourmark-notary}"
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  submit_dmg "keychain profile $PROFILE" --keychain-profile "$PROFILE"
elif [[ -n "${APPLE_API_KEY:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER:-}" ]]; then
  submit_dmg "App Store Connect API key" \
    --key "$APPLE_API_KEY" \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER"
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  submit_dmg "Apple ID" \
    --apple-id "$APPLE_ID" \
    --team-id "${APPLE_TEAM_ID:-R4SB7G9A32}" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD"
elif [[ "${REQUIRE_NOTARIZATION:-}" == "1" ]]; then
  echo "Notarization credentials are missing." >&2
  echo "Set APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_SPECIFIC_PASSWORD." >&2
  exit 1
else
  echo "DMG is Developer ID–signed. Add notary credentials to staple a ticket."
  echo "See docs/apple-distribution.md"
  exit 0
fi

echo "→ Stapling…"
xcrun stapler staple "$DMG"
echo "✓ Notarized: $DMG"
