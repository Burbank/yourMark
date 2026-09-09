# yourMark for Windows — early

The Mac app is the real product. Windows cannot run that Swift window, so this folder is a **small companion**: drop a file, Microsoft MarkItDown writes Markdown on this PC.

It does **not** yet have the library, bookmarks, pictures folder, Ask, or Settings from the Mac app. Those take weeks, not an afternoon.

## What you need

1. [Python 3.12+](https://www.python.org/downloads/) — tick **Add python.exe to PATH**.
2. A terminal in this folder:

```bat
py -m pip install "markitdown[all]"
py yourmark.py
```

3. Click **Choose files**, pick a PDF (or Word, slides, Excel). **Convert** writes a `.md` next to the file and opens that folder.

First convert may take a minute while MarkItDown finishes installing.

## What this is not

- Not a copy of the Mac window.
- Not Docling / OCR for scans yet.
- Not an `.exe` installer yet (that comes after this window is useful).

The converter is the same [Microsoft MarkItDown](https://github.com/microsoft/markitdown) the Mac app uses.
