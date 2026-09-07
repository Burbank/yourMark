#!/usr/bin/env python3
"""Call Microsoft MarkItDown through the Python API.

The CLI only exposes a slice of the library. This wrapper uses the
documented local path:

  convert_local()          — never fetch URIs (Microsoft security note)
  StreamInfo               — extension / filename so the right converter wins
  keep_data_uris           — Office + image files keep embedded pictures
  style_map                — Word Title / Quote / Caption → Markdown
  exiftool_path            — image EXIF when ExifTool is on this Mac
  enable_plugins           — official plugins (markitdown-ocr, RTF sample)
  llm_client / llm_prompt  — PPTX + image captions, and OCR plugin text
  result.title             — YAML front matter when MarkItDown has a title

API key is read from the environment, never from argv.
Azure Document Intelligence / Content Understanding are not used.
"""
from __future__ import annotations

import json
import os
import shutil
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
p[style-name='Heading 1'] => h1:fresh
p[style-name='Heading 2'] => h2:fresh
p[style-name='Heading 3'] => h3:fresh
"""

# Formats whose converters actually emit <img> / data URIs.
KEEP_DATA_URI = {
    "docx", "pptx", "xlsx", "ppt", "xls",
    "html", "htm",
    "jpg", "jpeg", "png", "gif", "webp", "tif", "tiff",
}


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


def _exiftool() -> str | None:
    home = os.path.expanduser("~")
    for path in (
        "/opt/homebrew/bin/exiftool",
        "/usr/local/bin/exiftool",
        f"{home}/.local/bin/exiftool",
        shutil.which("exiftool"),
    ):
        if path and os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    return None


def _yaml_scalar(value: str) -> str:
    text = value.replace("\n", " ").strip()
    if not text:
        return '""'
    if any(ch in text for ch in ":#{}[]&*!|>'\"%@`") or text[:1] in "-?":
        return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return text


def _with_title(markdown: str, title: str | None, source_name: str) -> str:
    if markdown.lstrip().startswith("---"):
        return markdown
    title = (title or "").strip()
    if not title:
        return markdown
    return (
        "---\n"
        f"title: {_yaml_scalar(title)}\n"
        f"source: {_yaml_scalar(source_name)}\n"
        "---\n\n"
        + markdown
    )


def main() -> int:
    if len(sys.argv) < 3:
        return 2
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    from markitdown import MarkItDown

    # Plugins are off in MarkItDown unless we turn them on. Official
    # markitdown-ocr silently no-ops without llm_client; the sample RTF
    # plugin only matches .rtf. Always enable so both can run.
    kwargs: dict = {"enable_plugins": True}
    tool = _exiftool()
    if tool:
        kwargs["exiftool_path"] = tool
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
    kwargs["style_map"] = STYLE_MAP
    md = MarkItDown(**kwargs)

    ext = src.suffix.lower().lstrip(".")
    convert_kw: dict = {}
    if ext in KEEP_DATA_URI:
        convert_kw["keep_data_uris"] = True
    try:
        from markitdown import StreamInfo

        convert_kw["stream_info"] = StreamInfo(
            extension="." + ext if ext else None,
            filename=src.name,
            local_path=str(src),
        )
    except Exception:
        pass

    # Microsoft: call the narrowest API. convert() also accepts http(s).
    if hasattr(md, "convert_local"):
        result = md.convert_local(str(src), **convert_kw)
    else:
        result = md.convert(str(src), **convert_kw)
    text = getattr(result, "markdown", None) or getattr(result, "text_content", "") or ""
    text = _with_title(text, getattr(result, "title", None), src.name)
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(text, encoding="utf-8")
    return 0 if dst.exists() and dst.stat().st_size > 0 else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        sys.stderr.write(str(exc) + "\n")
        raise SystemExit(1)
