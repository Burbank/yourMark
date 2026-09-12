#!/bin/zsh
# Copy a relocatable CPython and install Microsoft MarkItDown into it.
# Used by the App Store flavor so first launch does not talk to PyPI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/Resources/BundledEngine}"
UV="${UV:-$(command -v uv)}"
[[ -n "$UV" && -x "$UV" ]] || { echo "uv is required to bundle MarkItDown" >&2; exit 1; }

echo "→ Locating CPython 3.12 (uv)…"
"$UV" python install 3.12 >/dev/null
PY="$("$UV" python find 3.12)"
[[ -x "$PY" ]] || { echo "uv python find 3.12 failed" >&2; exit 1; }
SRC="$(cd "$(dirname "$PY")/.." && pwd)"

echo "→ Copying $SRC → $DEST…"
rm -rf "$DEST"
mkdir -p "$DEST"
ditto --norsrc --noextattr --noqtn "$SRC" "$DEST"

BUNDLE_PY="$DEST/bin/python3"
[[ -x "$BUNDLE_PY" ]] || BUNDLE_PY="$DEST/bin/python3.12"
[[ -x "$BUNDLE_PY" ]] || { echo "bundled python missing" >&2; exit 1; }

# This is our private copy, not uv’s install. Drop the lock file so pip can write.
find "$DEST" -name EXTERNALLY-MANAGED -delete

echo "→ Installing markitdown[all] into the copy (no network after the app is built)…"
"$UV" pip install --python "$BUNDLE_PY" --upgrade "markitdown[all]"

echo "→ Checking…"
"$BUNDLE_PY" -m markitdown --version
echo "✓ Bundled engine: $DEST"
du -sh "$DEST"
