# Install yourMark

## No Terminal (recommended)

1. Download [yourMark.dmg](https://github.com/Burbank/yourMark/releases/latest/download/yourMark.dmg).
2. Drag **yourMark** into Applications.
3. Double-click **Install Engine** on the disk image (Microsoft MarkItDown, once).
4. Open yourMark. If macOS blocks it: System Settings → Privacy & Security → **Open Anyway**.

macOS 14 or newer.

## Homebrew (optional)

Homebrew is not required. Use it if you already have brew:

```sh
brew tap Burbank/yourMark
brew install --cask yourmark
uv tool install 'markitdown[all]'
```

## Terminal

```sh
curl -LsSf https://astral.sh/uv/install.sh | sh
uv tool install 'markitdown[all]'
git clone https://github.com/Burbank/yourMark.git
cd yourMark
chmod +x Scripts/Install.command
./Scripts/Install.command
```

`Install.command` is also double-clickable in Finder.

## Uninstall

```sh
rm -rf /Applications/yourMark.app
rm -rf ~/Library/Application\ Support/yourMark
uv tool uninstall markitdown   # optional — only if you do not need MarkItDown elsewhere
```

## Site

[burbank.github.io/yourMark](https://burbank.github.io/yourMark/)
