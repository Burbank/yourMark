#!/bin/zsh
# Build the direct-download yourmark CLI (never -DAPPSTORE), sign it with
# Developer ID Application, notarize a zip, and write a SHA-256 checksum.
# The App Store stub is a different build: it prints a message and exits 4.
#
# REQUIRE_NOTARIZATION=1  fail if the binary cannot be signed and notarized.
# YOURMARK_SKIP_SIGN=1    build and zip only (local packaging check).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# One --arch per invocation. Passing both arches together uses the Xcode
# build graph, which on Xcode 16 leaves SWIFT_VERSION empty and fails.
echo "→ Building yourmark-cli per architecture (release, no -DAPPSTORE)…"

find_cli() {
  local scratch="$1"
  local candidate
  for candidate in \
    "$scratch/out/Products/Release/yourmark-cli" \
    "$scratch/Products/Release/yourmark-cli" \
    "$scratch/apple/Products/Release/yourmark-cli" \
    "$scratch/release/yourmark-cli"
  do
    if [[ -f "$candidate" ]]; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}

build_arch() {
  local arch="$1"
  local scratch="$ROOT/.build/cli-$arch"
  rm -rf "$scratch"
  echo "→ swift build -c release --product yourmark-cli --arch $arch --scratch-path .build/cli-$arch"
  swift build -c release --product yourmark-cli --arch "$arch" --scratch-path "$scratch"
  local bin info
  if ! bin=$(find_cli "$scratch"); then
    echo "yourmark-cli for $arch was not produced under $scratch" >&2
    exit 1
  fi
  info=$(lipo -info "$bin" 2>/dev/null || true)
  if [[ "$info" != *"$arch"* ]]; then
    echo "$bin is not an $arch binary ($info)" >&2
    exit 1
  fi
  BUILT="$bin"
}

BUILT=""
build_arch arm64
ARM_BIN="$BUILT"
build_arch x86_64
X64_BIN="$BUILT"

mkdir -p "$ROOT/.build/cli-universal"
BIN="$ROOT/.build/cli-universal/yourmark-cli"
rm -f "$BIN"
lipo -create "$ARM_BIN" "$X64_BIN" -output "$BIN"
info=$(lipo -info "$BIN" 2>/dev/null || true)
if [[ "$info" != *"arm64"* || "$info" != *"x86_64"* ]]; then
  echo "lipo did not produce an arm64+x86_64 yourmark-cli ($info)" >&2
  exit 1
fi

echo "→ $(lipo -info "$BIN")"

help_text=$("$BIN" --help)
if [[ "$help_text" == *"not available in the App Store build"* || "$help_text" != *"convert"* ]]; then
  echo "Refusing to package the App Store CLI stub." >&2
  exit 1
fi

VERSION=$("$BIN" --version 2>/dev/null | tail -n 1 | awk '{print $NF}')
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Could not read a version from yourmark-cli --version" >&2
  exit 1
fi

STAGE="$ROOT/dist/cli-stage"
DEST="$STAGE/yourmark"
ZIP_NAME="yourmark-cli-${VERSION}-macos.zip"
SHA_NAME="yourmark-cli-${VERSION}-macos.sha256"
ZIP="$ROOT/dist/$ZIP_NAME"
SHA="$ROOT/dist/$SHA_NAME"

rm -rf "$STAGE"
mkdir -p "$STAGE" "$ROOT/dist"
cp "$BIN" "$DEST"
chmod 755 "$DEST"
xattr -cr "$DEST" >/dev/null 2>&1 || true

sign_binary() {
  local identity="$1"
  echo "→ Signing yourmark (Developer ID, hardened runtime, timestamp)…"
  codesign --force --options runtime --timestamp --sign "$identity" "$DEST"
  local sig
  sig=$(codesign --display --verbose=4 "$DEST" 2>&1 || true)
  if [[ "$sig" != *"Developer ID Application"* || "$sig" != *"runtime"* || "$sig" != *"Timestamp="* ]]; then
    echo "codesign did not apply Developer ID, hardened runtime, and a timestamp." >&2
    exit 1
  fi
  codesign --verify --verbose=2 "$DEST"
  echo "→ Signature OK (Developer ID Application, hardened runtime, timestamp)"
}

IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ "${YOURMARK_SKIP_SIGN:-}" == "1" ]]; then
  echo "→ YOURMARK_SKIP_SIGN=1; not signing"
elif [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')
fi

if [[ "${YOURMARK_SKIP_SIGN:-}" == "1" ]]; then
  echo "→ Zip will be unsigned"
elif [[ -n "$IDENTITY" ]]; then
  sign_binary "$IDENTITY"
elif [[ "${REQUIRE_NOTARIZATION:-}" == "1" ]]; then
  echo "No Developer ID Application identity in the keychain." >&2
  echo "Import APPLE_DEVELOPER_ID_P12 before packaging the CLI." >&2
  exit 1
else
  echo "→ No Developer ID identity; zip will be unsigned"
fi

make_zip() {
  rm -f "$ZIP"
  # A single Mach-O at the zip root. --keepParent would nest it under cli-stage,
  # and AppleDouble (._yourmark) makes notarytool reject the archive.
  (
    cd "$STAGE"
    COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr yourmark "$ZIP"
  )
  local listing
  listing=$(unzip -l "$ZIP")
  if [[ "$listing" == *"cli-stage/"* || "$listing" == *"._yourmark"* || "$listing" != *" yourmark"* ]]; then
    echo "CLI zip layout is wrong:" >&2
    echo "$listing" >&2
    exit 1
  fi
}

write_checksum() {
  (
    cd "$ROOT/dist"
    shasum -a 256 "$ZIP_NAME" > "$SHA_NAME"
  )
}

make_zip

# 0 = accepted, 1 = credentials not set, 2 = notarytool failed.
notarize_zip() {
  local profile="${NOTARY_PROFILE:-yourmark-notary}"
  if xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
    echo "→ Submitting CLI zip to notarytool (keychain profile)…"
    xcrun notarytool submit "$ZIP" --keychain-profile "$profile" --wait || return 2
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    echo "→ Submitting CLI zip to notarytool (Apple ID)…"
    xcrun notarytool submit "$ZIP" \
      --apple-id "$APPLE_ID" \
      --team-id "${APPLE_TEAM_ID:-R4SB7G9A32}" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --wait || return 2
  elif [[ -n "${APPLE_API_KEY:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER:-}" ]]; then
    echo "→ Submitting CLI zip to notarytool (App Store Connect API key)…"
    xcrun notarytool submit "$ZIP" \
      --key "$APPLE_API_KEY" \
      --key-id "$APPLE_API_KEY_ID" \
      --issuer "$APPLE_API_ISSUER" \
      --wait || return 2
  else
    return 1
  fi
}

notary_status=0
if [[ "${YOURMARK_SKIP_SIGN:-}" != "1" ]]; then
  set +e
  notarize_zip
  notary_status=$?
  set -e
fi

if [[ "$notary_status" -eq 0 && "${YOURMARK_SKIP_SIGN:-}" != "1" ]]; then
  echo "→ Notary accepted the zip. Stapling the binary…"
  if xcrun stapler staple "$DEST"; then
    make_zip
    echo "→ Stapled ticket is inside the re-zipped binary"
  else
    echo "→ stapler did not staple the bare executable. The zip notarytool accepted is the one we ship (Gatekeeper checks the online ticket)."
  fi
elif [[ "$notary_status" -eq 1 && "${REQUIRE_NOTARIZATION:-}" == "1" ]]; then
  echo "Notarization credentials are missing." >&2
  echo "Set APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_SPECIFIC_PASSWORD." >&2
  exit 1
elif [[ "$notary_status" -eq 1 ]]; then
  echo "→ Notary credentials not set; zip is not notarized"
elif [[ "$notary_status" -ne 0 ]]; then
  echo "notarytool did not accept the CLI zip." >&2
  exit 1
fi

write_checksum

echo "✓ CLI zip: $ZIP"
echo "✓ Checksum: $SHA"
cat "$SHA"

# The staged binary is only an input to the zip.
rm -rf "$STAGE"
