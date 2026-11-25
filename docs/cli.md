# yourMark CLI

The `yourmark` command-line tool converts documents to Markdown using the same conversion pipeline as the yourMark GUI app. It is not inside `yourMark.app`.

## Installation

Download the signed, notarized command from the latest GitHub release. You need macOS 14 or later. The zip holds one universal binary (Apple silicon and Intel) named `yourmark`.

[yourmark-cli-0.6.4-macos.zip](https://github.com/Burbank/yourMark/releases/latest/download/yourmark-cli-0.6.4-macos.zip) · [SHA-256](https://github.com/Burbank/yourMark/releases/latest/download/yourmark-cli-0.6.4-macos.sha256)

```bash
unzip yourmark-cli-0.6.4-macos.zip
mkdir -p "$HOME/.local/bin"
mv yourmark "$HOME/.local/bin/yourmark"
```

Put `$HOME/.local/bin` on your PATH, then run `yourmark doctor`.

The Mac App Store build is sandboxed. That copy of the command prints `yourmark CLI is not available in the App Store build.` and exits 4.

### Build from source

Swift 6 (Xcode) builds the same command. A source build is not notarized.

```bash
swift build -c release --product yourmark-cli
```

The product file is named `yourmark-cli` (`.build/release/yourmark-cli`, or `.build/out/Products/Release/yourmark-cli` on a newer toolchain). Copy it to `yourmark` on your PATH so the command name matches `yourmark --help`.

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
- `--ocr-engine <engine>` - OCR engine: `auto` (default), `vision`, or `tesseract`. `auto` uses OCRmyPDF when it is installed, otherwise Apple Vision.
- `--layout <mode>` - Reading order: `auto` (default), `docling`, or `off`. `auto` puts the body first and sidebars after it, without splitting words. `off` leaves the converter's own order. `docling` asks Docling for the reading order.
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

# Apple Vision, and leave the converter's own reading order
yourmark convert scan.pdf --out ~/Library --ocr on --ocr-engine vision --layout off

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

## OCR engine

`--ocr-engine` chooses who reads a scan. From `yourmark convert --help`:

- `auto` - OCRmyPDF when it is installed, otherwise Apple Vision (default)
- `vision` - Apple Vision
- `tesseract` - OCRmyPDF + Tesseract when `ocrmypdf` is installed, otherwise Apple Vision

## Layout

`--layout` chooses reading order. From `yourmark convert --help`:

- `auto` - Body first, then sidebars, without splitting words (default)
- `docling` - Ask Docling for the reading order
- `off` - Leave the converter's own order

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
- The App Store build's command prints `yourmark CLI is not available in the App Store build.` and exits 4
