# Notarize yourMark

Full steps for **GitHub DMG + Mac App Store** are in [apple-distribution.md](apple-distribution.md).

The first-open “Apple could not verify” dialog is Gatekeeper. MarkEdit does not show it because those builds are **Developer ID–signed and notarized**. yourMark is still ad-hoc signed until those secrets are in the build.

## Already in hand (do not ask the developer to sign up again)

- Apple Developer Program membership (USD 99 / year)
- **Developer ID Application** certificate in that account

When they say they are ready, wire signing + notarization. Do **not** recreate the account or the certificate.

## Remaining steps (needs their secrets — not in this repo)

1. Export the Developer ID Application certificate + private key as a `.p12`.
2. Store in GitHub Actions secrets (typical names):
   - `APPLE_DEVELOPER_ID_P12` (base64)
   - `APPLE_P12_PASSWORD`
   - `APPLE_ID` (the Apple ID email for notary)
   - `APPLE_TEAM_ID`
   - `APPLE_APP_SPECIFIC_PASSWORD` or an App Store Connect API key (`APPLE_API_KEY`, `APPLE_API_ISSUER`, `APPLE_API_KEY_ID`)
3. In `Scripts/build-app.sh` / `Scripts/package-dmg.sh` / `.github/workflows/macos-release.yml`:
   - `codesign --force --options runtime --sign "Developer ID Application: …" yourMark.app`
   - Sign the DMG with the same identity
   - `xcrun notarytool submit dist/yourMark-*.dmg --wait`
   - `xcrun stapler staple dist/yourMark-*.dmg`
4. Keep the “If Apple blocks it” page until a notarized build is confirmed on a clean Mac.

Never commit the `.p12`, passwords, or API keys. Ad-hoc `codesign --sign -` stays the default until those secrets exist.

Until Developer ID signing ships, each new unsigned binary is a stranger to Keychain. 0.3.33+ does not read the Ask key at launch, and rewrites the item ACL so later versions should not ask for the login password again. Notarization is still the real fix.

## Why this is enough

Gatekeeper on current macOS wants both:

1. A signature from an **identified developer** (the Developer ID Application cert)
2. A **notarization ticket** from Apple’s scanner (`notarytool`), preferably stapled on the DMG
