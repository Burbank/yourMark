# Install yourMark

## No Terminal (recommended)

1. Download [yourMark.dmg](https://github.com/Burbank/yourMark/releases/latest/download/yourMark.dmg).
2. Drag **yourMark** into Applications.
3. If macOS says it cannot verify the app, **do not Move to Bin**. Double-click **If macOS blocks yourMark** on the disk image. Or: right-click yourMark → **Open**. Or: System Settings → Privacy & Security → **Open Anyway**.
4. Open yourMark. It installs **Microsoft MarkItDown** itself the first time (official PyPI package — not a copy inside the app).

macOS 14 or newer. The warning is Gatekeeper: this build is not notarized yet.

## Homebrew (optional)

Homebrew is not required. Use it if you already have brew:

```sh
brew tap Burbank/yourMark
brew install --cask yourmark
```

First launch still installs MarkItDown if it is missing.

## Terminal

```sh
curl -LsSf https://astral.sh/uv/install.sh | sh
uv tool install 'markitdown[all]'
git clone https://github.com/Burbank/yourMark.git
cd yourMark
chmod +x Scripts/Install.command
./Scripts/Install.command
```

## Uninstall

```sh
rm -rf /Applications/yourMark.app
rm -rf ~/Library/Application\ Support/yourMark
uv tool uninstall markitdown   # optional — only if you do not need MarkItDown elsewhere
```

## Site

[burbank.github.io/yourMark](https://burbank.github.io/yourMark/)
