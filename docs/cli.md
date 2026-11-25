# yourMark CLI

The `yourmark` command-line tool converts documents to Markdown using the same conversion pipeline as the yourMark GUI app.

## Installation

The CLI is included in the yourMark app bundle. Add it to your PATH:

```bash
# If yourMark.app is in /Applications
export PATH="/Applications/yourMark.app/Contents/MacOS:$PATH"

# Or create a symlink
ln -s /Applications/yourMark.app/Contents/MacOS/yourmark /usr/local/bin/yourmark
```

## Commands

### convert

Convert a document to Markdown.

```bash
yourmark convert <file.pdf|https-url> --out <library-dir> [options]
```

**Arguments:**
- `<file.pdf|https-url>` - Local file path or HTTPS URL to convert

**Options:**
- `--out <dir>` - Output library directory (required)
- `--ocr <mode>` - OCR mode: `auto` (default), `on`, or `off`
- `--images <mode>` - Extract images: `on` or `off` (default: `off`)
- `--keep-original <mode>` - Keep original PDF: `auto` (default), `always`, or `never`
- `--max-mb <size>` - Maximum file size in MB (default: 100)
- `--max-pages <count>` - Maximum pages (default: 1500)
- `--timeout <seconds>` - Timeout in seconds, or `auto` (default: `auto`)
- `--ocr-lang <lang>` - OCR language: `auto` (default), `eng`, `nld`, `spa`, or `hun`
- `--json` - Output JSON instead of human-readable text
- `--dry-run` - Check inputs without converting

**Output folder structure:**
```
<out>/<Title>/
  <Title>.md              # Converted Markdown
  <Title>.outline.json    # Document outline (if available)
  figures/                # Extracted images (if --images on)
    figure-001.jpg
    figure-002.jpg
  <original>.pdf          # Original PDF (if kept)
```

**Examples:**
```bash
# Convert a local PDF
yourmark convert paper.pdf --out ~/Documents/Library

# Convert from URL with OCR
yourmark convert https://example.com/doc.pdf --out ~/Library --ocr on

# Extract images
yourmark convert paper.pdf --out ~/Library --images on

# Dutch OCR
yourmark convert scan.pdf --out ~/Library --ocr-lang nld

# JSON output
yourmark convert paper.pdf --out ~/Library --json
```

### fetch

Download a file from an HTTPS URL.

```bash
yourmark fetch <https-url> --out <dir> [options]
```

**Arguments:**
- `<https-url>` - HTTPS URL to download

**Options:**
- `--out <dir>` - Output directory (required)
- `--max-mb <size>` - Maximum file size in MB (default: 100)
- `--json` - Output JSON

**Security:**
- Only HTTPS URLs are supported
- Maximum 5 redirects, all must be HTTPS
- No cookies or authentication
- Content-Type must be `application/pdf` or `application/octet-stream`
- File must start with PDF magic bytes (`%PDF-`)
- Encrypted/password PDFs are rejected

**Examples:**
```bash
yourmark fetch https://example.com/paper.pdf --out ~/Downloads
yourmark fetch https://example.com/paper.pdf --out ~/Downloads --json
```

### probe

Inspect a PDF file.

```bash
yourmark probe <file.pdf> [--json]
```

**Output:**
- Pages
- Has text layer (yes/no)
- Scanned pages (count)
- Encrypted (yes/no)
- Size
- SHA-256 hash

**Examples:**
```bash
yourmark probe paper.pdf
yourmark probe paper.pdf --json
```

### doctor

Check converter installation and dependencies.

```bash
yourmark doctor [--json]
```

**Output:**
- Distribution channel (direct or mas)
- MarkItDown path and version
- uv path and version
- Docling path and version
- OCRmyPDF path and version
- Tesseract path, version, and languages
- Vision availability

**Examples:**
```bash
yourmark doctor
yourmark doctor --json
```

## Exit Codes

| Code | Status | Meaning |
|------|--------|---------|
| 0 | ok | Conversion succeeded |
| 1 | partial | Conversion completed with warnings |
| 2 | rejected | Input rejected (limits, policy, encryption) |
| 3 | failed | Conversion failed (processing error) |
| 4 | engine_missing | MarkItDown not installed (App Store build) |
| 5 | io_error | Output or file system error |
| 124 | timeout | Conversion exceeded timeout |

## JSON Output

When `--json` is passed, the CLI outputs a single JSON object on stdout and logs to stderr.

### Success

```json
{
  "status": "ok",
  "version": "0.6.4",
  "source_url": "https://example.com/paper.pdf",
  "sha256": "abc123...",
  "pages": 42,
  "ocr_pages": 0,
  "ocr_engine": "",
  "weak_ocr": false,
  "images": 0,
  "original_kept": false,
  "folder": "/Users/me/Library/Paper Title",
  "md_path": "/Users/me/Library/Paper Title/Paper Title.md",
  "figures_dir": "",
  "bytes_md": 125000,
  "warnings": [],
  "elapsed_s": 12.5
}
```

### Error

```json
{
  "status": "rejected",
  "error": {
    "code": 2,
    "message": "File exceeds size limit: 150MB > 100MB"
  }
}
```

## OCR Modes

- `auto` - Detect scans automatically and OCR if needed (default)
- `on` - Force OCR for all PDFs
- `off` - Disable OCR, use MarkItDown only

## OCR Languages

The CLI supports multilingual OCR via Apple Vision:

- `auto` - Detect language automatically (default)
- `eng` - English
- `nld` - Dutch
- `spa` - Spanish
- `hun` - Hungarian

For other languages, the CLI uses Tesseract when available.

## Timeout Calculation

When `--timeout auto` is used (default), the timeout is calculated as:

```
timeout = clamp(120 + 3*pages + 20*ocrPages, 120, 3600)
```

- Minimum: 120 seconds (2 minutes)
- Maximum: 3600 seconds (1 hour)
- Base: 120 seconds
- Per page: 3 seconds
- Per OCR page: 20 seconds

## Keep Original PDF

The `--keep-original` option controls when the original PDF is copied into the output folder:

- `auto` - Keep if OCR was used and quality is weak (mean confidence < 0.6 or < 200 chars/page)
- `always` - Always keep the original
- `never` - Never keep the original

## Notes

- The CLI never deletes or moves the input file
- URLs are stripped of query parameters and fragments before logging
- No repository secrets are used
- The App Store build (`APPSTORE`) does not include the CLI
