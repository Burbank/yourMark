# yourMark for Windows — early

**[Download yourMark.exe](https://github.com/Burbank/yourMark/releases/latest/download/yourMark.exe)** — double-click. No Python install.

This is **not** the Mac app. It turns a PDF (or Word, slides, Excel) into Markdown on this PC. No library, bookmarks, Ask, or Settings yet.

Windows may say **Windows protected your PC** (SmartScreen). That is the same kind of caution as Apple on a Mac — this build is not signed yet. Click **More info** → **Run anyway**.

Choose files, then **Convert**. A folder opens with the `.md`.

## If you prefer Python

```bat
py -m pip install "markitdown[pdf]"
py yourmark.py
```

Or without a window: `py yourmark.py --cli handbook.pdf`

The converter is the same [Microsoft MarkItDown](https://github.com/microsoft/markitdown) the Mac app uses.
