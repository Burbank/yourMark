# Install yourMark

## Double-click (recommended)

1. Download [yourMark-0.5.0.dmg](https://github.com/Burbank/yourMark/releases/latest/download/yourMark-0.5.0.dmg) (the filename includes the version).
2. Open the disk image and **drag yourMark onto Applications** (follow the arrow). Then open yourMark from Applications.

This Mac disk is signed and notarized by Apple.

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

A Shortcut or Terminal can hand a file to yourMark (put your file’s full path after `file=`):

```sh
open 'yourmark://convert?file=/Users/you/Manual.pdf'
```

## Uninstall

```sh
rm -rf /Applications/yourMark.app
rm -rf ~/Library/Application\ Support/yourMark
uv tool uninstall markitdown   # optional — only if you do not need MarkItDown elsewhere
```

## Site

Use the same program in the browser: [burbank.github.io/yourMark](https://burbank.github.io/yourMark/)
