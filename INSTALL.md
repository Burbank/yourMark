# Install yourMark

## Double-click (recommended)

1. Download [yourMark.dmg](https://github.com/Burbank/yourMark/releases/latest/download/yourMark.dmg).
2. Open the disk image and **double-click Install yourMark**. That copies the app to Applications, clears the macOS quarantine flag, and launches it.

### If macOS says it “could not verify” the app

That dialog is Gatekeeper. This build is not notarized yet, so Apple cannot vouch for it. It is expected.

1. Click **Done** — not **Move to Bin**.
2. Double-click **If macOS blocks yourMark** on the disk image.
3. Or: right-click yourMark → **Open**.
4. Or: System Settings → Privacy & Security → **Open Anyway**.

Then open yourMark. The first launch **installs Microsoft MarkItDown itself** (official PyPI package — not a copy inside the app). Needs the internet once.

macOS 14 or newer.

## Homebrew (optional)

```sh
brew tap Burbank/yourMark
brew install --cask yourmark
```

First launch still installs MarkItDown if it is missing.

## Terminal

```sh
git clone https://github.com/Burbank/yourMark.git
cd yourMark
chmod +x Scripts/Install.command
./Scripts/Install.command
```

The app installs MarkItDown on first launch. To do that step yourself:

```sh
curl -LsSf https://astral.sh/uv/install.sh | sh
uv tool install 'markitdown[all]'
```

## Uninstall

```sh
rm -rf /Applications/yourMark.app
rm -rf ~/Library/Application\ Support/yourMark
uv tool uninstall markitdown   # optional — only if you do not need MarkItDown elsewhere
```

## Site

Use the same program in the browser: [burbank.github.io/yourMark](https://burbank.github.io/yourMark/)
