# yourMark

<p align="center">
  <img src="docs/icon.png" width="112" height="112" alt="yourMark">
</p>

A Mac app that turns PDFs — and Word, slides, or a spreadsheet — into **Markdown**. That is ordinary text you can search, copy, and ask questions about. The file never leaves this computer.

**[Download yourMark-0.3.37.dmg](https://github.com/Burbank/yourMark/releases/latest/download/yourMark-0.3.37.dmg)** · [All versions](https://github.com/Burbank/yourMark/releases) · [Install notes](INSTALL.md) · [Same page in a browser](https://burbank.github.io/yourMark/)

## Why Markdown?

A PDF is a picture of a page. Markdown is the words, in order.

That is why it works so well with AI. A model can read a chapter, quote it, and say when the file is silent — instead of guessing at a scan. Paste a heading into Grok or ChatGPT, keep notes, or search a whole course. Tables stay tables. Headings stay an outline.

Keep the original PDF. Markdown is the working copy.

## A look inside

The window has three places:

- **Convert** — drop a PDF, Word, slides, or Excel. The words are written on this Mac.
- **Library** — file on the left, bookmarks in the middle, the text on the right. Ask a chapter at the bottom if you add a key.
- **Settings** — Bright, Dim, or System colours in the header; an optional AI key; extra help for scanned pages.

yourMark is the window. [Microsoft MarkItDown](https://github.com/microsoft/markitdown) does the converting, on this Mac. If Microsoft publishes an update, yourMark can install it for you.

Needs **macOS 14** or later. Open the disk and **drag yourMark onto Applications** (follow the arrow). Do not keep working from the disk — if you do, yourMark will copy itself into Applications so ejecting is safe. The first launch installs MarkItDown if it is missing.

If Apple says it could not verify the app: click **Done** (not Move to Bin), then open **If Apple blocks it** on the disk — a help page in Safari, not a program — or right-click yourMark → Open. That warning is normal until the app is notarized. It is not malware.

## Pictures of the window

<br>

<img src="docs/shots/library-dim.jpg" width="880" alt="yourMark library at night: files on the left, bookmarks in the middle, Markdown on the right">

<br>

Library at night — files, bookmarks, and the text. Ask a chapter underneath. Bookmarks jump like Preview.

<br>

| <img src="docs/shots/library-bright.jpg" width="420" alt="Library in Bright"> | <img src="docs/shots/convert-dim.jpg" width="420" alt="Convert in Dim"> |
| --- | --- |
| Library · Bright — the same three columns on paper. | Convert — drop a PDF. Nothing is uploaded. |
| <img src="docs/shots/convert-bright.jpg" width="420" alt="Convert in Bright"> | <img src="docs/shots/settings-dim.jpg" width="420" alt="Settings in Dim"> |
| Convert · Bright — this 787 handbook kept 595 bookmarks from the PDF itself. | Settings — paste a key, press Enter. Extra tools are only for scans. |

<br>

## Changing the text

yourMark is a **reader**. To change the file, press **Edit**. That opens [MarkEdit](https://github.com/MarkEdit-app/MarkEdit), a free Mac editor. Get it from Settings if it is not installed. You do not need a GitHub account. Saves in MarkEdit show up here.

## What you get

| You asked | What you actually get |
|-----------|------------------------|
| **Tables** | Yes, when the PDF has a real table. Colours and merged cells become plain cells. |
| **Pictures** | The photos that were inside the PDF, next to that page. We do not add photographs of whole text pages. The Markdown and a `figures` folder sit together in a little folder named after the file. |
| **Headers / footers** | **Remove headers and footers** in Settings (on by default) drops repeating page titles, page numbers, dates, and header logos. Chapter titles like 8.1 stay. |
| **Bookmarks** | The same outline Preview shows becomes headings in the Markdown. Numbered titles (8.1, 8.1.1) become headings too. |
| **Other files** | Word, PowerPoint, Excel, web pages, EPUB, CSV, mail, RTF, ZIP (each file inside), and photos. |

## Install

**Everyone:** download the disk image, drag **yourMark** onto **Applications** (follow the arrow), then open it. First launch installs Microsoft MarkItDown.

**Homebrew (optional):**

```sh
brew tap Burbank/yourMark
brew install --cask yourmark
```

**From source:** `./Scripts/Install.command`

**Windows (early):** a small companion lives in [`windows/`](windows/README.md). It uses the same Microsoft converter. It is not the Mac window yet — no library, bookmarks, or Ask.


### If Apple blocks the app

This build is not notarized yet, so macOS often shows **“yourMark.app” Not Opened** and offers **Move to Bin**. That is Apple being careful — not a virus.

![macOS dialog: yourMark.app Not Opened. Click Done, not Move to Bin.](docs/shots/not-opened.png)

1. Click **Done** — not **Move to Bin**.
2. Apple menu → **System Settings**.
3. Sidebar → **Privacy & Security**.
4. Scroll to **Security**.
5. Next to *“yourMark.app” was blocked to protect your Mac*, click **Open Anyway**.
6. Confirm **Open Anyway**.

![System Settings → Privacy & Security → Open Anyway](docs/shots/open-anyway.png)

You can also right-click yourMark → **Open**, or open **If Apple blocks it** on the disk (a page in Safari with a button into Settings).

## License

yourMark is MIT. MarkItDown is MIT, from Microsoft. Not an official Microsoft product.
