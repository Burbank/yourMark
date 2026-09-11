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

The GitHub disk from 0.3.47 on is Developer ID–signed and notarized. From 0.3.48 the disk is only the app and Applications — no Gatekeeper help files.

## 2. Mac App Store (second)

Apple forbids App Store apps from downloading and running new code. So this flavor:

- Sets `YourMarkDistribution=mas` in Info.plist
- Uses the App Sandbox (`Resources/YourMark.mas.entitlements`)
- Ships **Microsoft MarkItDown inside the app** (no PyPI after purchase)
- Scans use **Apple Live Text** (this copy cannot install Docling)
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
3. Support URL (listing only — do not put this on the public site, README, or GitHub Help): https://burbank.github.io/yourMark/support.html
   The page is `docs/support.html`. It is for the App Store copy. GitHub installs stay on Issues. After the listing is live, paste the `apps.apple.com` link into the reserved App Store slot on that page. The URL is live only after you push `docs/`.
4. App Privacy: we do not collect data. Ask keys stay on device; they are sent only to the provider the user picks.
5. Export compliance: HTTPS only (exempt).
6. Age rating: 4+ (no objectionable content).
7. Screenshots from `docs/shots/` (Mac 1280×800 and 2560×1600).
8. Review notes: conversion is on-device; Ask is optional and uses the user’s own key; no account.
9. Upload the `.pkg` with Transporter. Needs **3rd Party Mac Developer Application** + **Installer** certificates (same developer account).

Category suggestion: **Productivity** or **Education**.

## What still needs a human

- Create the App Store Connect listing (yourMark, `com.burbank.yourmark`)
- Create **Apple Distribution** + **Mac Installer Distribution** on team R4SB7G9A32 (keep Developer ID)
- Paste listing copy and 2560×1600 shots from `CURSOR_general_logs/yourMark/AppStore/`
- Then run `./Scripts/package-mas.sh` and upload the `.pkg` with Transporter
