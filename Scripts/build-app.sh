#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="yourMark"
EXEC_NAME="YourMark"
BUILD_DIR="$ROOT/.build"
APP_DIR="$ROOT/dist/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
INSTALL_APP="/Applications/${APP_NAME}.app"
SKIP_INSTALL="${SKIP_INSTALL:-0}"

echo "→ Building $EXEC_NAME (release)…"
swift build -c release --product "$EXEC_NAME"

BIN="$BUILD_DIR/release/$EXEC_NAME"
if [[ ! -x "$BIN" ]]; then
  echo "Build failed: missing $BIN" >&2
  exit 1
fi

echo "→ Assembling $APP_NAME.app…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN" "$MACOS/$EXEC_NAME"

if [[ -f "$ROOT/Resources/Help.html" ]]; then
  cp "$ROOT/Resources/Help.html" "$RESOURCES/Help.html"
fi

if [[ -f "$ROOT/Resources/AppIcon.png" ]]; then
  cp "$ROOT/Resources/AppIcon.png" "$RESOURCES/AppIcon.png"
fi
ICON_PLIST=""
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
  ICON_PLIST=$'\n\t<key>CFBundleIconFile</key>\n\t<string>AppIcon</string>'
elif [[ -f "$RESOURCES/AppIcon.png" ]] && command -v sips >/dev/null && command -v iconutil >/dev/null; then
  ICONSET="$ROOT/dist/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$RESOURCES/AppIcon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$RESOURCES/AppIcon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
  ICON_PLIST=$'\n\t<key>CFBundleIconFile</key>\n\t<string>AppIcon</string>'
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${EXEC_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>com.burbank.yourmark</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>yourMark</string>
	<key>CFBundleDisplayName</key>
	<string>yourMark</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.3.8</string>
	<key>CFBundleVersion</key>
	<string>20</string>${ICON_PLIST}
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSSupportsAutomaticGraphicsSwitching</key>
	<true/>
	<key>LSSupportsOpeningDocumentsInPlace</key>
	<false/>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>Convertible document</string>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
			<key>LSTypeIsPackage</key>
			<false/>
			<key>CFBundleTypeExtensions</key>
			<array>
				<string>pdf</string>
				<string>docx</string>
				<string>pptx</string>
				<string>xlsx</string>
				<string>md</string>
			</array>
			<key>LSItemContentTypes</key>
			<array>
				<string>com.adobe.pdf</string>
				<string>org.openxmlformats.wordprocessingml.document</string>
				<string>org.openxmlformats.presentationml.presentation</string>
				<string>org.openxmlformats.spreadsheetml.sheet</string>
				<string>net.daringfireball.markdown</string>
				<string>public.plain-text</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
PLIST

echo -n 'APPL????' > "$CONTENTS/PkgInfo"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

if [[ "$SKIP_INSTALL" == "1" ]]; then
  echo "✓ Built: $APP_DIR"
  exit 0
fi

echo "→ Installing to $INSTALL_APP…"
osascript -e 'tell application "yourMark" to quit' >/dev/null 2>&1 || true
sleep 0.4
rm -rf "$INSTALL_APP"
cp -R "$APP_DIR" "$INSTALL_APP"
codesign --force --deep --sign - "$INSTALL_APP" >/dev/null 2>&1 || true

echo "✓ Installed: $INSTALL_APP"
