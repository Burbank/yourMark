#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="yourMark"
EXEC_NAME="YourMark"
BUILD_DIR="$ROOT/.build"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
APP_DIR="$WORK/${APP_NAME}.app"
DIST_APP="$ROOT/dist/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
INSTALL_APP="/Applications/${APP_NAME}.app"
SKIP_INSTALL="${SKIP_INSTALL:-0}"
DISTRIBUTION="${DISTRIBUTION:-direct}"
if [[ "$DISTRIBUTION" != "mas" ]]; then
  DISTRIBUTION="direct"
fi
# App Store listing is "yourMark AI" (yourMark was taken). GitHub disk stays yourMark.
if [[ "$DISTRIBUTION" == "mas" ]]; then
  DISPLAY_NAME="yourMark AI"
else
  DISPLAY_NAME="yourMark"
fi

echo "→ Building $EXEC_NAME (release)…"
if [[ "$DISTRIBUTION" == "mas" ]]; then
  swift build -c release --product "$EXEC_NAME" -Xswiftc -DAPPSTORE
else
  swift build -c release --product "$EXEC_NAME"
fi

BIN="$BUILD_DIR/release/$EXEC_NAME"
if [[ ! -x "$BIN" ]]; then
  echo "Build failed: missing $BIN" >&2
  exit 1
fi

echo "→ Assembling $APP_NAME.app…"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN" "$MACOS/$EXEC_NAME"

if [[ -f "$ROOT/Resources/Help.html" ]]; then
  cp "$ROOT/Resources/Help.html" "$RESOURCES/Help.html"
fi
if [[ -f "$ROOT/Resources/pdf_enrich.py" ]]; then
  cp "$ROOT/Resources/pdf_enrich.py" "$RESOURCES/pdf_enrich.py"
fi
if [[ -f "$ROOT/Resources/markitdown_convert.py" ]]; then
  cp "$ROOT/Resources/markitdown_convert.py" "$RESOURCES/markitdown_convert.py"
fi
if [[ -f "$ROOT/Resources/PrivacyInfo.xcprivacy" ]]; then
  cp "$ROOT/Resources/PrivacyInfo.xcprivacy" "$RESOURCES/PrivacyInfo.xcprivacy"
fi
if [[ "$DISTRIBUTION" == "mas" ]]; then
  ENGINE="$ROOT/Resources/BundledEngine"
  if [[ ! -x "$ENGINE/bin/python3" && ! -x "$ENGINE/bin/python3.12" ]]; then
    echo "→ Bundling Microsoft MarkItDown (once, ~400 MB)…"
    chmod +x "$ROOT/Scripts/bundle-engine.sh"
    "$ROOT/Scripts/bundle-engine.sh" "$ENGINE"
  fi
  echo "→ Copying bundled converter…"
  ditto --norsrc --noextattr --noqtn "$ENGINE" "$RESOURCES/python"
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
	<string>${DISPLAY_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.5.1</string>
	<key>CFBundleVersion</key>
	<string>66</string>${ICON_PLIST}
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
	<key>YourMarkDistribution</key>
	<string>${DISTRIBUTION}</string>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2026 Arie Duister. MIT License.</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSSupportsAutomaticGraphicsSwitching</key>
	<true/>
	<key>LSSupportsOpeningDocumentsInPlace</key>
	<false/>
	<key>NSDownloadsFolderUsageDescription</key>
	<string>yourMark writes converted Markdown where you choose, including Downloads.</string>
	<key>NSDocumentsFolderUsageDescription</key>
	<string>yourMark writes converted Markdown next to files you open, including Documents.</string>
	<key>NSDesktopFolderUsageDescription</key>
	<string>yourMark writes converted Markdown next to files you open on the Desktop.</string>
	<key>NSUserNotificationsUsageDescription</key>
	<string>yourMark tells you when a file has finished converting to Markdown.</string>
	<key>NSAppManagementUsageDescription</key>
	<string>yourMark opens the Markdown in the editor you picked. It does not update or delete other apps.</string>
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>com.burbank.yourmark</string>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>yourmark</string>
			</array>
		</dict>
	</array>
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
				<string>xls</string>
				<string>html</string>
				<string>htm</string>
				<string>epub</string>
				<string>csv</string>
				<string>json</string>
				<string>xml</string>
				<string>msg</string>
				<string>jpg</string>
				<string>jpeg</string>
				<string>png</string>
				<string>gif</string>
				<string>webp</string>
				<string>tif</string>
				<string>tiff</string>
				<string>zip</string>
				<string>rtf</string>
				<string>md</string>
			</array>
			<key>LSItemContentTypes</key>
			<array>
				<string>com.adobe.pdf</string>
				<string>org.openxmlformats.wordprocessingml.document</string>
				<string>org.openxmlformats.presentationml.presentation</string>
				<string>org.openxmlformats.spreadsheetml.sheet</string>
				<string>com.microsoft.excel.xls</string>
				<string>public.html</string>
				<string>org.idpf.epub-container</string>
				<string>public.comma-separated-values-text</string>
				<string>public.json</string>
				<string>public.xml</string>
				<string>public.jpeg</string>
				<string>public.png</string>
				<string>com.compuserve.gif</string>
				<string>org.webmproject.webp</string>
				<string>public.tiff</string>
				<string>public.zip-archive</string>
				<string>public.rtf</string>
				<string>net.daringfireball.markdown</string>
				<string>public.plain-text</string>
			</array>
		</dict>
	</array>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>Convert with yourMark</string>
			</dict>
			<key>NSMessage</key>
			<string>convertWithYourMark</string>
			<key>NSPortName</key>
			<string>yourMark</string>
			<key>NSSendFileTypes</key>
			<array>
				<string>com.adobe.pdf</string>
				<string>org.openxmlformats.wordprocessingml.document</string>
				<string>org.openxmlformats.presentationml.presentation</string>
				<string>public.data</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
PLIST

echo "→ Building Share extension…"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
SHARE_BIN="$WORK/ShareToYourMark"
swiftc -O -parse-as-library \
  -target arm64-apple-macosx14.0 \
  -sdk "$SDK" \
  -application-extension \
  -module-name ShareToYourMark \
  -framework AppKit -framework UniformTypeIdentifiers \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$SHARE_BIN" \
  "$ROOT/Sources/ShareExtension/ShareViewController.swift"
PLUGIN="$CONTENTS/PlugIns/ShareToYourMark.appex"
mkdir -p "$PLUGIN/Contents/MacOS"
cp "$SHARE_BIN" "$PLUGIN/Contents/MacOS/ShareToYourMark"
cp "$ROOT/Resources/ShareExtension.Info.plist" "$PLUGIN/Contents/Info.plist"
if [[ -f "$RESOURCES/AppIcon.icns" ]]; then
  mkdir -p "$PLUGIN/Contents/Resources"
  cp "$RESOURCES/AppIcon.icns" "$PLUGIN/Contents/Resources/AppIcon.icns"
fi

echo -n 'APPL????' > "$CONTENTS/PkgInfo"
# iCloud Drive leaves Finder info that codesign rejects.
xattr -cr "$APP_DIR" >/dev/null 2>&1 || true

ENTITLEMENTS="$ROOT/Resources/YourMark.${DISTRIBUTION}.entitlements"
SIGN_ARGS=(--force --deep --sign -)
if [[ "$DISTRIBUTION" == "mas" ]]; then
  IDENTITY="${MAS_CODESIGN_IDENTITY:-}"
else
  IDENTITY="${CODESIGN_IDENTITY:-}"
fi
if [[ -z "${IDENTITY}" ]]; then
  if [[ "$DISTRIBUTION" == "mas" ]]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/3rd Party Mac Developer Application|Apple Distribution/{print $2; exit}')
    if [[ -z "${IDENTITY}" ]]; then
      IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/{print $2; exit}')
      if [[ -n "${IDENTITY}" ]]; then
        echo "→ No Mac App Store identity yet — signing as $IDENTITY for a local sandbox test"
        echo "   Upload needs Apple Distribution + Mac Installer Distribution (team R4SB7G9A32)."
      fi
    fi
  else
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')
  fi
fi
if [[ -n "${IDENTITY}" ]]; then
  echo "→ Signing as $IDENTITY ($DISTRIBUTION)…"
  if [[ "$DISTRIBUTION" == "mas" && -d "$RESOURCES/python" ]]; then
    echo "→ Signing bundled Python with App Sandbox…"
    chmod +x "$ROOT/Scripts/sign-nested-python.sh"
    "$ROOT/Scripts/sign-nested-python.sh" "$RESOURCES/python" "$IDENTITY"
  fi
  # Do not --deep: that stamps the app entitlements on Python and the Share extension.
  SIGN_ARGS=(--force --options runtime --timestamp --sign "$IDENTITY")
  if [[ -f "$ENTITLEMENTS" ]]; then
    SIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
  fi
else
  echo "→ Ad-hoc sign (no Developer ID / Mac App Store identity in this keychain)"
  SIGN_ARGS=(--force --sign -)
  if [[ -f "$ENTITLEMENTS" ]]; then
    SIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
  fi
fi
if [[ -d "$CONTENTS/PlugIns/ShareToYourMark.appex" ]]; then
  SHARE_SIGN=(--force --sign -)
  if [[ -n "${IDENTITY}" ]]; then
    SHARE_SIGN=(--force --options runtime --timestamp --sign "$IDENTITY")
  fi
  if [[ -f "$ROOT/Resources/ShareExtension.entitlements" ]]; then
    SHARE_SIGN+=(--entitlements "$ROOT/Resources/ShareExtension.entitlements")
  fi
  echo "→ Signing Share extension…"
  codesign "${SHARE_SIGN[@]}" "$CONTENTS/PlugIns/ShareToYourMark.appex"
fi
codesign "${SIGN_ARGS[@]}" "$APP_DIR"

mkdir -p "$ROOT/dist"
rm -rf "$DIST_APP"
ditto --norsrc --noextattr --noqtn "$APP_DIR" "$DIST_APP"

if [[ "$SKIP_INSTALL" == "1" ]]; then
  echo "✓ Built: $DIST_APP"
  exit 0
fi

echo "→ Installing to $INSTALL_APP…"
osascript -e 'tell application "yourMark" to quit' >/dev/null 2>&1 || true
sleep 0.4
rm -rf "$INSTALL_APP"
ditto --norsrc --noextattr --noqtn "$APP_DIR" "$INSTALL_APP"
codesign "${SIGN_ARGS[@]}" "$INSTALL_APP"

echo "✓ Installed: $INSTALL_APP"
