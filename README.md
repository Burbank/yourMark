# yourMark

Native **macOS** SwiftUI wrapper around [Microsoft MarkItDown](https://github.com/microsoft/markitdown) — convert PDFs, Word, PowerPoint, and Excel to Markdown **on this Mac**. Built for students, researchers, and anyone who would rather search a document than scroll it.

The GUI never vendors the converter: it discovers `markitdown` on PATH / uv and **Upgrade Engine** pulls the current PyPI release. Same family as [Ghostscript GUI](https://github.com/Burbank/ghostscript-gui): thin local CLI wrapper.

**Requires:** macOS 14+, Xcode (to build), and MarkItDown via uv or pip.

Keep your original files. Converted Markdown is for search, bookmarks, and asking a chapter.

---

## What conversion actually keeps

| You asked | Honest result |
|-----------|----------------|
| **Tables with formatting** | Yes when the PDF has a *real* table — GitHub-flavored Markdown tables (columns + cell text). Colours, merged cells, and drawn-line “tables” flatten. |
| **Pictures in the right position** | In **reading order**, not the original page layout. Word/PPTX usually emit `![]()` figures. Microsoft’s default PDF path is text + tables; scans/drawings need extras. |
| **Outline / bookmarks like a PDF** | Yes. yourMark reads the PDF outline (same tree as Preview.app) and also builds bookmarks from Markdown headings. Click to jump. |

---

## Install the engine (once)

```sh
# recommended — stays current independently of this app
uv tool install 'markitdown[all]'
markitdown --version
```

Or: `pip3 install -U 'markitdown[all]'`

## Build the app

```sh
./Scripts/build-app.sh
open -a yourMark
```

Dev run:

```sh
swift run YourMark
```

## After install

| Route | How |
|------|-----|
| **Applications** | `/Applications/yourMark.app` |
| **Open With** | Right-click a PDF → Open With → **yourMark** |
| **Upgrade engine** | yourMark → Engine → Upgrade MarkItDown (`uv tool upgrade markitdown`) |
| **Help** | Help → yourMark Help (⌘?) |

## Why this instead of a downloaded .dmg GUI

Packaged community GUIs pin `markitdown==0.1.x` at build time. yourMark is the Ghostscript-GUI pattern: **your** `markitdown` binary, upgraded from PyPI, no fork of Microsoft’s code.

## Bundle

- Identifier: `com.burbank.yourmark`
- Team: use your Apple Developer team when you are ready to notarize / App Store

## License

This repository is a macOS GUI wrapper. MarkItDown is MIT from Microsoft.
