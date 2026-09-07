# yourMark

Native **macOS** SwiftUI wrapper around [Microsoft MarkItDown](https://github.com/microsoft/markitdown). Convert PDFs, Word, PowerPoint, and Excel to Markdown **on this Mac**.

**[Download for Mac](https://github.com/Burbank/yourMark/releases/latest/download/yourMark.dmg)** · [Install notes](INSTALL.md) · [Website](https://burbank.github.io/yourMark/)

The GUI never vendors the converter. It finds `markitdown` on this Mac; **Upgrade Engine** pulls the current PyPI release.

**Requires:** macOS 14+. The DMG is for everyone. Building from source needs Xcode.

Keep the original file. Markdown is for search, bookmarks, and asking a chapter.

---

## What conversion actually keeps

| You asked | Honest result |
|-----------|----------------|
| **Tables** | Yes when the PDF has a real table (GFM). Colours / merged cells flatten. |
| **Pictures** | Reading order, not page x/y. Word/PPTX usually include them. |
| **Outline** | PDF bookmarks + Markdown headings. Click to jump. |

---

## Install

**Everyone:** download the DMG, drag the app to Applications, double-click **Install Engine**.

**Homebrew (optional):**

```sh
brew tap Burbank/yourMark
brew install --cask yourmark
uv tool install 'markitdown[all]'
```

**From source:** `./Scripts/Install.command` or `./Scripts/build-app.sh`

## License

MIT wrapper. MarkItDown is MIT from Microsoft.
