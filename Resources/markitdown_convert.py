#!/usr/bin/env python3
"""Call Microsoft MarkItDown through the Python API.

The CLI only exposes a slice of the library. This wrapper passes:
  - keep_data_uris for Word/PowerPoint/Excel images
  - a mammoth style_map so Word Title/Quote styles become headings
  - optional llm_client (OpenAI-compatible) for image captions and
    the official markitdown-ocr plugin (text inside pictures)

API key is read from the environment, never from argv.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

STYLE_MAP = """
p[style-name='Title'] => h1:fresh
p[style-name='Subtitle'] => h2:fresh
p[style-name='Heading'] => h1:fresh
p[style-name='Quote'] => blockquote:fresh
p[style-name='Intense Quote'] => blockquote:fresh
p[style-name='Caption'] => p:fresh
p[style-name='List Paragraph'] => p:fresh
"""


class _Msg:
    def __init__(self, content: str) -> None:
        self.content = content


class _Choice:
    def __init__(self, content: str) -> None:
        self.message = _Msg(content)


class _Resp:
    def __init__(self, content: str) -> None:
        self.choices = [_Choice(content)]


class _Completions:
    def __init__(self, base: str, key: str) -> None:
        self.base = base.rstrip("/")
        self.key = key

    def create(self, model: str, messages: list, **_kwargs):
        url = self.base + "/chat/completions"
        body = json.dumps({"model": model, "messages": messages, "max_tokens": 400}).encode()
        req = urllib.request.Request(
            url,
            data=body,
            headers={
                "Content-Type": "application/json",
                "Authorization": "Bearer " + self.key,
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=90) as resp:
            payload = json.loads(resp.read().decode("utf-8", errors="replace"))
        text = (
            payload.get("choices", [{}])[0]
            .get("message", {})
            .get("content", "")
            or ""
        )
        return _Resp(text)


class _Chat:
    def __init__(self, base: str, key: str) -> None:
        self.completions = _Completions(base, key)


class CompatClient:
    """Minimum OpenAI-compatible client MarkItDown's llm_caption expects."""

    def __init__(self, base: str, key: str) -> None:
        self.chat = _Chat(base, key)


def main() -> int:
    if len(sys.argv) < 3:
        return 2
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    from markitdown import MarkItDown

    kwargs: dict = {"enable_plugins": os.environ.get("YOURMARK_LLM_KEY", "").strip() != ""}
    key = os.environ.get("YOURMARK_LLM_KEY", "").strip()
    if key:
        base = os.environ.get("YOURMARK_LLM_BASE", "https://api.openai.com/v1").strip()
        model = os.environ.get("YOURMARK_LLM_MODEL", "gpt-4o").strip() or "gpt-4o"
        kwargs["llm_client"] = CompatClient(base, key)
        kwargs["llm_model"] = model
        kwargs["llm_prompt"] = (
            "Describe this picture for a student studying the document. "
            "Read any labels, numbers, switch names, or table cells you can see. "
            "Two or three short sentences. Do not invent values."
        )
    md = MarkItDown(**kwargs)
    convert_kw: dict = {"style_map": STYLE_MAP}
    ext = src.suffix.lower().lstrip(".")
    if ext in {"docx", "pptx", "xlsx", "ppt", "xls", "html", "htm"}:
        convert_kw["keep_data_uris"] = True
    result = md.convert(str(src), **convert_kw)
    text = getattr(result, "markdown", None) or getattr(result, "text_content", "") or ""
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(text, encoding="utf-8")
    return 0 if dst.exists() and dst.stat().st_size > 0 else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        sys.stderr.write(str(exc) + "\n")
        raise SystemExit(1)
