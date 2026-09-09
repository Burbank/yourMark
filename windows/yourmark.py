#!/usr/bin/env python3
"""Small Windows window: pick files, run Microsoft MarkItDown, open the folder.

This is not the Mac app. It reuses the same convert script so a PDF on
Windows gets the same engine as yourMark on a Mac.

  py yourmark.py              → window (needs Tk)
  py yourmark.py --cli FILE   → no window, just convert
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SCRIPT = ROOT / "markitdown_convert.py"
if not SCRIPT.exists():
    SCRIPT = ROOT.parent / "Resources" / "markitdown_convert.py"

KINDS = [
    ("Documents", "*.pdf *.docx *.pptx *.xlsx *.html *.htm *.epub *.zip"),
    ("PDF", "*.pdf"),
    ("All files", "*.*"),
]


def python_exe() -> str:
    return sys.executable


def ensure_engine() -> str:
    """Return a python that can `import markitdown`, installing if needed."""
    py = python_exe()
    check = subprocess.run(
        [py, "-c", "import markitdown"],
        capture_output=True,
        text=True,
    )
    if check.returncode == 0:
        return py
    subprocess.check_call([py, "-m", "pip", "install", "markitdown[all]"])
    return py


def convert_one(py: str, src: Path, log) -> Path:
    src = src.expanduser().resolve()
    if not src.is_file():
        raise FileNotFoundError(src)
    out_dir = src.with_name(src.stem)
    out_dir.mkdir(exist_ok=True)
    dest = out_dir / (src.stem + ".md")
    log(f"Converting {src.name}…")
    if not SCRIPT.exists():
        raise FileNotFoundError(f"Missing convert script: {SCRIPT}")
    proc = subprocess.run(
        [py, str(SCRIPT), str(src), str(dest)],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "convert failed").strip()
        raise RuntimeError(err[-1200:])
    log(f"Wrote {dest}")
    return dest


def run_cli(paths: list[str]) -> int:
    def log(msg: str) -> None:
        print(msg, flush=True)

    try:
        log("Checking Microsoft MarkItDown…")
        py = ensure_engine()
        last = None
        for item in paths:
            last = convert_one(py, Path(item), log)
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
            "Use:  python yourmark.py --cli yourfile.pdf",
            file=sys.stderr,
        )
        return 2

    class App(tk.Tk):
        def __init__(self) -> None:
            super().__init__()
            self.title("yourMark for Windows (early)")
            self.geometry("560x420")
            self.minsize(480, 360)
            self.files: list[Path] = []

            pad = {"padx": 16, "pady": 6}
            ttk.Label(
                self,
                text="This is a first Windows window. It turns a PDF into Markdown\n"
                "on this PC. The Mac app is still the full yourMark.",
                justify="left",
            ).pack(anchor="w", **pad)

            btns = ttk.Frame(self)
            btns.pack(fill="x", **pad)
            ttk.Button(btns, text="Choose files…", command=self.choose).pack(side="left")
            ttk.Button(btns, text="Convert", command=self.start).pack(side="left", padx=8)
            ttk.Button(btns, text="Clear list", command=self.clear).pack(side="left")

            self.listbox = tk.Listbox(self, height=8)
            self.listbox.pack(fill="both", expand=True, padx=16, pady=4)

            self.status = tk.Text(self, height=7, wrap="word")
            self.status.pack(fill="both", expand=False, padx=16, pady=(4, 16))
            self.log("Ready. Choose a PDF, then Convert.")

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
                self.log("Checking Microsoft MarkItDown…")
                py = ensure_engine()
                last = None
                for src in list(self.files):
                    last = convert_one(py, src, self.log)
                self.log("Done.")
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
            print("Usage: python yourmark.py --cli file.pdf", file=sys.stderr)
            return 2
        return run_cli(args.files)
    if args.files:
        return run_cli(args.files)
    return run_gui()


if __name__ == "__main__":
    sys.exit(main())
