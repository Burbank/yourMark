# Apple distribution (GitHub + App Store)

Two channels, one codebase. Do **not** recreate the Apple Developer account or certificates. Team ID: **R4SB7G9A32** (Arie Duister — same team as GearUp, Quicklog, FDP FMS, wallaX).

## 1. Notarized GitHub DMG (first)

This is the full app: Microsoft MarkItDown, optional IBM Docling, write-beside-PDF, GitHub updates.

Already in hand: Apple Developer Program, **Developer ID Application** certificate.

### Secrets (GitHub Actions → Settings → Secrets)

| Secret | What it is |
|--------|------------|
| `APPLE_DEVELOPER_ID_P12` | Developer ID Application cert + key, base64 of a `.p12` |
| `APPLE_P12_PASSWORD` | Password for that `.p12` |
| `APPLE_TEAM_ID` | Team ID: `R4SB7G9A32` |
| `APPLE_ID` | Apple ID email |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for notary **or** |
| `APPLE_API_KEY` / `APPLE_API_KEY_ID` / `APPLE_API_ISSUER` | App Store Connect API key (`.p8` path or file on the runner) |

Never commit the `.p12`, passwords, or API keys.

### Local

```sh
export CODESIGN_IDENTITY="Developer ID Application: …"
# optional: xcrun notarytool store-credentials yourmark-notary
./Scripts/package-dmg.sh
```

`Scripts/build-app.sh` uses Developer ID when that identity is in the keychain; otherwise it stays ad-hoc. `Scripts/sign-and-notarize.sh` staples a ticket when notary credentials exist.

Keep the “If Apple blocks it” page on the disk until a notarized build opens on a clean Mac.

## 2. Mac App Store (second)

Apple forbids App Store apps from downloading and running new code. So this flavor:

- Sets `YourMarkDistribution=mas` in Info.plist
- Uses the App Sandbox (`Resources/YourMark.mas.entitlements`)
- Converts with **Apple PDFKit + Live Text** (no PyPI, no Docling install)
- Defaults Markdown to the yourMark library folder
- Hides GitHub / PyPI update buttons (updates come from the App Store)

```sh
./Scripts/bundle-engine.sh          # once — Microsoft MarkItDown inside the app (~380 MB)
DISTRIBUTION=mas ./Scripts/package-mas.sh
```

Open `YourMark.xcodeproj` for team, sandbox, and the **AppStore** configuration (`APPSTORE` flag). `Scripts/build-app.sh` still assembles the `.app` used for testing.

Then in App Store Connect:

1. Create the Mac app `yourMark`, bundle ID `com.burbank.yourmark`.
2. Privacy policy URL: https://burbank.github.io/yourMark/privacy.html
3. App Privacy: we do not collect data. Ask keys stay on device; they are sent only to the provider the user picks.
4. Export compliance: HTTPS only (exempt).
5. Age rating: 4+ (no objectionable content).
6. Screenshots from `docs/shots/` (Mac 1280×800 and 2560×1600).
7. Review notes: conversion is on-device; Ask is optional and uses the user’s own key; no account.
8. Upload the `.pkg` with Transporter. Needs **3rd Party Mac Developer Application** + **Installer** certificates (same developer account).

Category suggestion: **Productivity** or **Education**.

## What still needs a human

- Import Developer ID into this keychain (only “Apple Development” is here today)
- Add the GitHub secrets above
- Create the App Store Connect listing
- First notarized tag (`v0.3.47` or later) after secrets are in
