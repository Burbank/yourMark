#!/usr/bin/env python3
"""Small Windows window: pick files, run Microsoft MarkItDown, open the folder.

Frozen as yourMark.exe so Windows users do not need Python.

  yourMark.exe                 → window
  yourMark.exe --cli FILE      → no window, just convert
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import threading
import webbrowser
from pathlib import Path

KINDS = [
    ("Documents", "*.pdf *.docx *.pptx *.xlsx *.html *.htm *.epub *.zip"),
    ("PDF", "*.pdf"),
    ("All files", "*.*"),
]

MARKTEXT_PAGE = "https://github.com/marktext/marktext/releases/latest"


def app_dir() -> Path:
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        return Path(sys._MEIPASS)
    here = Path(__file__).resolve().parent
    if (here / "markitdown_convert.py").exists():
        return here
    return here.parent / "Resources"


def find_marktext() -> Path | None:
    which = shutil.which("MarkText") or shutil.which("marktext")
    if which:
        return Path(which)
    roots = [
        os.environ.get("LOCALAPPDATA", ""),
        os.environ.get("PROGRAMFILES", ""),
        os.environ.get("PROGRAMFILES(X86)", ""),
    ]
    for root in roots:
        if not root:
            continue
        for rel in (
            Path("Programs") / "MarkText" / "MarkText.exe",
            Path("MarkText") / "MarkText.exe",
        ):
            cand = Path(root) / rel
            if cand.is_file():
                return cand
    return None


def convert_one(src: Path, log) -> Path:
    src = src.expanduser().resolve()
    if not src.is_file():
        raise FileNotFoundError(src)
    out_dir = src.with_name(src.stem)
    out_dir.mkdir(exist_ok=True)
    dest = out_dir / (src.stem + ".md")
    log(f"Converting {src.name}…")
    root = str(app_dir())
    if root not in sys.path:
        sys.path.insert(0, root)
    try:
        import markitdown  # noqa: F401
    except ImportError:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "markitdown[pdf]"])
    import markitdown_convert as conv

    rc = conv.convert_file(src, dest)
    if rc:
        raise RuntimeError("MarkItDown could not write that file.")
    log(f"Wrote {dest}")
    return dest


def run_cli(paths: list[str]) -> int:
    def log(msg: str) -> None:
        try:
            print(msg, flush=True)
        except Exception:
            pass

    try:
        last = None
        for item in paths:
            last = convert_one(Path(item), log)
        log("Done.")
        if last and sys.platform == "win32" and shutil.which("explorer"):
            subprocess.Popen(["explorer", "/select,", str(last)])
        return 0
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


def run_gui() -> int:
    try:
        import tkinter as tk
        from tkinter import filedialog, messagebox, ttk
    except ImportError:
        print(
            "No window library (Tk) on this computer.\n"
            "Use:  yourMark.exe --cli yourfile.pdf",
            file=sys.stderr,
        )
        return 2

    class App(tk.Tk):
        def __init__(self) -> None:
            super().__init__()
            self.title("yourMark for Windows (early)")
            self.geometry("580x500")
            self.minsize(500, 420)
            self.files: list[Path] = []
            self.last_md: Path | None = None

            pad = {"padx": 16, "pady": 6}
            ttk.Label(
                self,
                text="This is a first Windows window. It turns a PDF into Markdown\n"
                "on this PC. The Mac app is still the full yourMark.",
                justify="left",
            ).pack(anchor="w", **pad)

            ttk.Label(
                self,
                text="yourMark is a reader. MarkEdit is Mac-only. On Windows, a good\n"
                "free open-source editor is MarkText. Get it once, then open the .md there.",
                justify="left",
            ).pack(anchor="w", **pad)

            btns = ttk.Frame(self)
            btns.pack(fill="x", **pad)
            ttk.Button(btns, text="Choose files…", command=self.choose).pack(side="left")
            ttk.Button(btns, text="Convert", command=self.start).pack(side="left", padx=8)
            ttk.Button(btns, text="Clear list", command=self.clear).pack(side="left")
            self.edit_btn = ttk.Button(btns, text="Get MarkText", command=self.marktext)
            self.edit_btn.pack(side="left", padx=8)
            self.refresh_edit_btn()

            self.listbox = tk.Listbox(self, height=7)
            self.listbox.pack(fill="both", expand=True, padx=16, pady=4)

            self.status = tk.Text(self, height=7, wrap="word")
            self.status.pack(fill="both", expand=False, padx=16, pady=(4, 16))
            self.log("Ready. Choose a PDF, then Convert.")

        def refresh_edit_btn(self) -> None:
            if find_marktext():
                self.edit_btn.configure(text="Open in MarkText")
            else:
                self.edit_btn.configure(text="Get MarkText")

        def marktext(self) -> None:
            exe = find_marktext()
            if exe and self.last_md and self.last_md.is_file():
                subprocess.Popen([str(exe), str(self.last_md)])
                return
            if exe:
                subprocess.Popen([str(exe)])
                return
            webbrowser.open(MARKTEXT_PAGE)
            self.log("Opened MarkText download. Install it, then press Open in MarkText.")
            self.refresh_edit_btn()

        def log(self, msg: str) -> None:
            self.status.insert("end", msg + "\n")
            self.status.see("end")
            self.update_idletasks()

        def choose(self) -> None:
            picked = filedialog.askopenfilenames(title="Files to convert", filetypes=KINDS)
            for item in picked:
                path = Path(item)
                if path not in self.files:
                    self.files.append(path)
                    self.listbox.insert("end", path.name)

        def clear(self) -> None:
            self.files.clear()
            self.listbox.delete(0, "end")

        def start(self) -> None:
            if not self.files:
                messagebox.showinfo("yourMark", "Choose a file first.")
                return
            threading.Thread(target=self.run_jobs, daemon=True).start()

        def run_jobs(self) -> None:
            try:
                last = None
                for src in list(self.files):
                    last = convert_one(src, self.log)
                self.log("Done.")
                self.last_md = last
                self.refresh_edit_btn()
                if last:
                    self.log("To change the Markdown, open it in MarkText (Get MarkText if you do not have it).")
                if last and sys.platform == "win32" and shutil.which("explorer"):
                    subprocess.Popen(["explorer", "/select,", str(last)])
            except Exception as exc:
                self.log(f"Error: {exc}")
                messagebox.showerror("yourMark", str(exc))

    App().mainloop()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="yourMark for Windows (early)")
    parser.add_argument("--cli", action="store_true", help="convert files without a window")
    parser.add_argument("files", nargs="*", help="files to convert (with --cli)")
    args = parser.parse_args()
    if args.cli:
        if not args.files:
            print("Usage: yourMark.exe --cli file.pdf", file=sys.stderr)
            return 2
        return run_cli(args.files)
    if args.files:
        return run_cli(args.files)
    return run_gui()


if __name__ == "__main__":
    sys.exit(main())
