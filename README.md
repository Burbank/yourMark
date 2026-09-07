# yourMark

<p align="center">
  <img src="docs/icon.png" width="112" height="112" alt="yourMark">
</p>

Native **macOS** SwiftUI wrapper around [Microsoft MarkItDown](https://github.com/microsoft/markitdown). Convert PDFs, Word, PowerPoint, and Excel to Markdown **on this Mac**.

**[Download yourMark-0.3.18.dmg](https://github.com/Burbank/yourMark/releases/latest/download/yourMark-0.3.18.dmg)** · [All releases](https://github.com/Burbank/yourMark/releases) · [Install notes](INSTALL.md) · [Use it in the browser](https://burbank.github.io/yourMark/)

## Why Markdown

A PDF is a picture of a page. Markdown is the words, in order, as plain text you can search and edit.

That is why it works so well with AI. A model can read a chapter, quote it, and tell you when the file is silent — instead of guessing at columns or a scan. Paste one heading into Grok or ChatGPT, keep notes in Obsidian, or search a whole course. Tables stay tables. Headings stay an outline.

Keep the original PDF. Markdown is the working copy.

The GUI never vendors the converter. It finds `markitdown` on this Mac; **Upgrade Engine** pulls the current PyPI release.

**Requires:** macOS 14+. Open the disk image and **drag yourMark onto Applications** (follow the arrow). First launch installs Microsoft MarkItDown from PyPI if it is missing. Building from source needs Xcode.

If macOS says it could not verify the app: click **Done** (not Move to Bin), then open **If Apple blocks it** on the disk (a web page, not a program), or right-click yourMark → Open. That warning is Gatekeeper (not notarized yet) — not malware.

---

## What conversion actually keeps

| You asked | Honest result |
|-----------|----------------|
| **Tables** | Yes when the PDF has a real table (GFM). Colours / merged cells flatten. |
| **Pictures** | Pulled from the PDF into a `*-figures` folder and linked in page order. Word/PPTX use MarkItDown’s own images. Not the original x/y layout. |
| **Outline** | PDF bookmarks + Markdown headings. Click to jump. |

---

## Install

**Everyone:** download the DMG, drag **yourMark** onto **Applications** (follow the arrow), then open it. First launch installs Microsoft MarkItDown.

**Homebrew (optional):**

```sh
brew tap Burbank/yourMark
brew install --cask yourmark
uv tool install 'markitdown[all]'
```

**From source:** `./Scripts/Install.command` or `./Scripts/build-app.sh`

---

### If Apple blocks the app

This build is not notarized, so macOS often shows **“yourMark.app” Not Opened** and offers **Move to Bin**. That is Gatekeeper, not malware.

<p align="center">
  <img src="docs/shots/not-opened.png" width="340" alt="macOS dialog: yourMark.app Not Opened. Apple could not verify yourMark.app is free of malware. Buttons: Done, Move to Bin.">
</p>

1. Click **Done** — not **Move to Bin**.
2. Apple menu → **System Settings**.
3. Sidebar → **Privacy & Security**.
4. Scroll to **Security** (near the bottom of that pane).
5. Next to *“yourMark.app” was blocked to protect your Mac*, click **Open Anyway**.
6. Confirm **Open Anyway** on the next dialog.

<p align="center">
  <img src="docs/shots/open-anyway.png" width="720" alt="System Settings → Privacy & Security → Security. Allow applications from: App Store & Known Developers. yourMark.app was blocked to protect your Mac — Open Anyway.">
</p>

You can also right-click yourMark → **Open**, or open **If Apple blocks it** on the disk image (a short web page with a button into System Settings).

## License

MIT wrapper. MarkItDown is MIT from Microsoft.
