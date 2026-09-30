### Mac version, most complete

Drag yourMark onto Applications (follow the arrow). This disk is signed and notarized by Apple. First launch installs Microsoft MarkItDown from PyPI.

**0.6.4** — A line with a space between every letter is restored from the PDF’s own words. A repeating header, footer, or page number is left out of the file the converter reads. The book title and author from that header are kept once at the top when they were not already known. The Markdown starts with a catalog record — title, author, publisher, date, rights, description, subject, language, and ISBN — taken from the PDF, the copyright page, and a catalog lookup for anything still missing. Make EPUB carries that record into the EPUB. A title is always written. If the PDF and the catalog do not have it, the opening of the book is read when an Ask key is saved; otherwise the file name is used.

**0.6.3** — A chapter stays with its own text when the outline lists two chapters on the same page. A Roman numeral under a heading, and the title repeated under it, are removed. A heading that stopped mid-phrase joins the next line. A long sentence that was marked as a heading returns to the paragraph. A line that is only a citation stays ordinary text. Clicking a chapter puts that heading at the top of the window.

**0.6.2** — Opening a conversion cleans the page. A page number that appears twice is kept once, so a sentence is not cut in half. A header, footer, or site address that repeats, an empty page, and a small picture of a size that repeats are removed. A character the converter could not read is dropped. A large initial on its own line joins the word that follows. A heading that wrapped onto a second line is one heading again. A line much longer than the lines around it wraps at a period or a comma. Deleting a library card can also move that conversion’s files to the Trash. The original PDF stays.

**0.6.1** — Make EPUB joins a split word such as “Wh en” when the two pieces are one real word. Two real words side by side stay apart. A contents line that ends in a page number is a link to that page, without the long row of dots. The front page of the original PDF is the cover: the thumbnail in the reader, and the first page of the EPUB. Make the EPUB again and copy that file to the device.

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
