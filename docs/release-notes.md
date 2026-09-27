### Mac version, most complete

Drag yourMark onto Applications (follow the arrow). This disk is signed and notarized by Apple. First launch installs Microsoft MarkItDown from PyPI.

**0.6.0** — Rendered draws a Markdown table as a grid and drops a column that is empty in every row. Make EPUB writes that table into an EPUB beside the Markdown. A plain-text copy of a table is removed, and a sentence that a table split is placed back above it. Hunter-Gatherer uses the same headings, bold, page marks, and tables. Foraging across two or more cells copies a Markdown table.

Rejoin, beside Convert, repairs split words such as “Ma ny”. Every convert also joins a hyphen at the end of a line to the next line. Remove page numbers is its own switch under Remove headers and footers, off unless you turn it on. The regular reader lets a drag cross more than one sentence.

**0.5.1** — Open or drop a Markdown file you already have; it skips the converter. Choose a folder on first launch; new `.md` files there appear in the library. Show in Finder highlights the little folder when there are pictures, so you can compress that for AI. Translate appears with a Google Translate key or an Ask AI key — either one is enough.

**Translate** sits in the reader toolbar: pick From and To, then This chapter or Entire file. Below keeps the original; Replace shows only the translation. Save a copy writes a second file. The original Markdown is not overwritten. Convert still stays on this Mac.

A Shortcut or Terminal can hand a file to yourMark: `yourmark://convert?file=/Users/you/Manual.pdf`

### Windows (early)

No library, bookmarks, Ask, or Translate. Same Microsoft converter.

1. Download **yourMark.exe**.
2. Double-click it. You do not need Python.
3. If Windows says **Windows protected your PC**, click **More info** → **Run anyway**.
4. Choose a PDF (or Word, slides, Excel), then **Convert**. A folder opens with the Markdown.
5. To change the file, use [MarkText](https://github.com/marktext/marktext) (free, open source). MarkEdit is Mac-only. The exe has a **Get MarkText** button.
