#!/bin/zsh
# Double-click to install Microsoft MarkItDown (the converter yourMark uses).
# No Terminal knowledge required — this window is the installer.
set -euo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

echo ""
echo "  yourMark — install the converter"
echo "  Microsoft MarkItDown, on this Mac only."
echo ""

if ! command -v uv >/dev/null 2>&1; then
  echo "  Installing uv…"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

echo "  Installing markitdown…"
uv tool install -q 'markitdown[all]' || uv tool upgrade markitdown

if command -v markitdown >/dev/null 2>&1; then
  echo "  ✓ $(markitdown --version 2>/dev/null | head -1)"
else
  echo "  Could not find markitdown on PATH."
  echo "  Open a new Terminal window and try:  uv tool install 'markitdown[all]'"
  read -k 1 -s "?  Press any key to close. "
  exit 1
fi

APP="/Applications/yourMark.app"
HERE="$(cd "$(dirname "$0")" && pwd)"
if [[ -d "$HERE/yourMark.app" ]]; then
  echo "  Copying yourMark to Applications…"
  rm -rf "$APP"
  cp -R "$HERE/yourMark.app" "$APP"
fi

if [[ -d "$APP" ]]; then
  echo "  Opening yourMark…"
  xattr -cr "$APP" >/dev/null 2>&1 || true
  open "$APP"
else
  echo "  App not in Applications yet. Drag yourMark.app onto the Applications folder, then open it."
fi

echo ""
echo "  Done. You can close this window."
echo ""
read -k 1 -s "?  Press any key to close. "
