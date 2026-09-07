#!/bin/zsh
# Double-click installer for yourMark (app + converter).
set -euo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo ""
echo "  yourMark installer"
echo ""

if ! command -v uv >/dev/null 2>&1; then
  echo "  Installing uv…"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

echo "  Installing Microsoft MarkItDown…"
uv tool install -q 'markitdown[all]' || uv tool upgrade markitdown

if [[ -d "$ROOT/dist/yourMark.app" ]]; then
  echo "  Installing app to /Applications…"
  SKIP_INSTALL=0
  rm -rf /Applications/yourMark.app
  cp -R "$ROOT/dist/yourMark.app" /Applications/yourMark.app
elif command -v swift >/dev/null 2>&1; then
  echo "  Building yourMark (needs Xcode once)…"
  chmod +x "$ROOT/Scripts/build-app.sh"
  "$ROOT/Scripts/build-app.sh"
else
  echo "  Download the DMG from https://github.com/Burbank/yourMark/releases"
  echo "  and drag yourMark into Applications."
  read -k 1 -s "?  Press any key to close. "
  exit 1
fi

xattr -cr /Applications/yourMark.app >/dev/null 2>&1 || true
open -a yourMark
echo "  ✓ Installed. You can close this window."
read -k 1 -s "?  Press any key to close. "
