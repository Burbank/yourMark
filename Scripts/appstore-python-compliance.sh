#!/bin/zsh
# App Review Guideline 2.5.2: CPython 3.12 urllib lists the scheme "itms-services"
# so urlparse treats it as having a network location. The app never opens that
# scheme. Apple still rejects the literal. Same patch CPython ships for the
# Mac App Store (Mac/Resources/app-store-compliance.patch).
set -euo pipefail

ROOT="${1:-}"
if [[ -z "$ROOT" || ! -d "$ROOT" ]]; then
  echo "usage: appstore-python-compliance.sh <BundledEngine-or-app/Contents/Resources/python>" >&2
  exit 1
fi

PARSE=""
for candidate in \
  "$ROOT/lib/python3.12/urllib/parse.py" \
  "$ROOT/lib/python3.13/urllib/parse.py" \
  "$ROOT/lib/python3.11/urllib/parse.py"
do
  if [[ -f "$candidate" ]]; then
    PARSE="$candidate"
    break
  fi
done

if [[ -z "$PARSE" ]]; then
  echo "note: no urllib/parse.py under $ROOT — nothing to patch"
  exit 0
fi

LIBDIR="$(dirname "$(dirname "$PARSE")")"
if grep -q "itms-services" "$PARSE"; then
  echo "→ Removing itms-services from $PARSE"
  /usr/bin/sed -i '' "s/, 'itms-services'//g" "$PARSE"
fi

# Stale bytecode still contains the rejected string.
find "$LIBDIR/urllib" -name 'parse*.pyc' -delete
find "$LIBDIR" -path '*__pycache__/parse.cpython-*.pyc' -delete

PY=""
for candidate in "$ROOT/bin/python3" "$ROOT/bin/python3.12" "$ROOT/bin/python3.13"; do
  if [[ -x "$candidate" ]]; then
    PY="$candidate"
    break
  fi
done

if [[ -n "$PY" ]]; then
  "$PY" - <<PY
import py_compile
from pathlib import Path
src = Path(r"""$PARSE""")
cache = src.parent / "__pycache__" / (src.stem + ".cpython-312.pyc")
if "3.13" in str(src):
    cache = src.parent / "__pycache__" / (src.stem + ".cpython-313.pyc")
cache.parent.mkdir(exist_ok=True)
py_compile.compile(str(src), cfile=str(cache), doraise=True)
print(f"→ compiled {cache}")
PY
fi

if rg -a -l "itms-services" "$ROOT" >/dev/null 2>&1; then
  echo "error: itms-services is still inside $ROOT" >&2
  rg -a -l "itms-services" "$ROOT" >&2 || true
  exit 1
fi

echo "ok: no itms-services in $ROOT"
