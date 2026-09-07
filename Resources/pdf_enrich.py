#!/usr/bin/env python3
"""Post-pass on MarkItDown PDF output using pdfplumber (already in markitdown[pdf]).

MarkItDown's local PDF converter keeps words and form-style tables, not
bookmarks, page markers, or every ruled table. This script:
  - inserts <!-- page N --> comments so Swift can map the PDF outline
  - weaves in pdfplumber tables that are missing from the Markdown

It never replaces MarkItDown's body text.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


def to_md(table: list[list[str | None]]) -> str:
    rows = []
    for row in table:
        cells = [("" if c is None else str(c).replace("\n", " ").strip()) for c in row]
        if not any(cells):
            continue
        rows.append(cells)
    if len(rows) < 2:
        return ""
    width = max(len(r) for r in rows)
    rows = [r + [""] * (width - len(r)) for r in rows]
    head = rows[0]
    lines = [
        "| " + " | ".join(head) + " |",
        "| " + " | ".join("---" for _ in head) + " |",
    ]
    for r in rows[1:]:
        lines.append("| " + " | ".join(r) + " |")
    return "\n".join(lines)


def main() -> int:
    if len(sys.argv) < 3:
        return 0
    pdf_path = Path(sys.argv[1])
    md_path = Path(sys.argv[2])
    if not pdf_path.exists() or not md_path.exists():
        return 0
    try:
        import pdfplumber
    except ImportError:
        return 0

    text = md_path.read_text(encoding="utf-8", errors="replace")
    has_pages = "<!-- page 1 -->" in text or "<!-- page 2 -->" in text
    table_count = text.count("\n| ---") + text.count("\n|---")

    inserts: list[tuple[str, str]] = []  # (needle, block)
    try:
        with pdfplumber.open(str(pdf_path)) as pdf:
            cap = min(len(pdf.pages), 220)
            for i, page in enumerate(pdf.pages[:cap]):
                marker = f"<!-- page {i + 1} -->"
                snippet = ""
                try:
                    raw = page.extract_text() or ""
                except Exception:
                    raw = ""
                for line in raw.splitlines():
                    line = line.strip()
                    if 28 <= len(line) <= 140:
                        snippet = line
                        break
                extra = []
                if table_count < 8:
                    try:
                        tables = page.extract_tables() or []
                    except Exception:
                        tables = []
                    for table in tables[:3]:
                        md = to_md(table or [])
                        if not md:
                            continue
                        # Skip if the first header already lives in the file.
                        first = (table[0][0] or "") if table and table[0] else ""
                        if first and first.strip() and first.strip() in text:
                            continue
                        extra.append(md)
                block_parts = []
                if not has_pages:
                    block_parts.append(marker)
                block_parts.extend(extra)
                if not block_parts:
                    continue
                block = "\n\n".join(block_parts) + "\n\n"
                if snippet and snippet in text:
                    inserts.append((snippet, block))
                elif not has_pages:
                    inserts.append(("", block))
    except Exception:
        return 0

    if not inserts:
        return 0

    out = text
    used = set()
    for snippet, block in inserts:
        if snippet and snippet in out and snippet not in used:
            used.add(snippet)
            idx = out.find(snippet)
            nl = out.find("\n", idx)
            at = nl + 1 if nl != -1 else idx + len(snippet)
            out = out[:at] + "\n" + block + out[at:]
        elif not snippet:
            out += "\n" + block

    if out != text:
        md_path.write_text(out, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
