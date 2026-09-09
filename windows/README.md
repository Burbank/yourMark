# yourMark for Windows — early

The Mac app is the real product. Windows cannot run that Swift window, so this folder is a **small companion**: drop a file, Microsoft MarkItDown writes Markdown on this PC.

It does **not** yet have the library, bookmarks, pictures folder, Ask, or Settings from the Mac app.

There is no Windows PC in the workshop, and no Windows simulator on the Mac. Convert is checked two ways:

1. On Linux, with `--cli` (no window).
2. On a real Windows machine at GitHub (`windows-latest`) every time this folder changes.

The window itself (Tk) still needs a person on Windows to click around.

## What you need

1. [Python 3.12+](https://www.python.org/downloads/) — tick **Add python.exe to PATH**.
2. A terminal in this folder:

```bat
py -m pip install "markitdown[all]"
py yourmark.py
```

Or without a window:

```bat
py yourmark.py --cli handbook.pdf
```

**Convert** writes a `.md` in a folder next to the file.

## What this is not

- Not a copy of the Mac window.
- Not Docling / OCR for scans yet.
- Not an `.exe` installer yet.

The converter is the same [Microsoft MarkItDown](https://github.com/microsoft/markitdown) the Mac app uses.
