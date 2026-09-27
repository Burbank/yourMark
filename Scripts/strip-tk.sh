#!/bin/zsh
# Remove Tcl/Tk from a bundled CPython. App Review rejects
# _NSWindowDidOrderOnScreenNotification (and sometimes Tcl_* symbols).
# MarkItDown never needs Tkinter.
set -euo pipefail

ROOT="${1:-}"
if [[ -z "$ROOT" || ! -d "$ROOT" ]]; then
  echo "usage: strip-tk.sh <BundledEngine-or-app/Contents/Resources/python>" >&2
  exit 1
fi

# Accept either the engine root or an .app
if [[ -d "$ROOT/Contents/Resources/python" ]]; then
  ROOT="$ROOT/Contents/Resources/python"
fi

removed=0
drop() {
  local p
  for p in "$@"; do
    [[ -e "$p" || -L "$p" ]] || continue
    rm -rf "$p"
    echo "removed ${p#$ROOT/}"
    removed=$((removed + 1))
  done
}

drop \
  "$ROOT/lib/libtcl9tk9.0.dylib" \
  "$ROOT/lib/libtcl9.0.dylib" \
  "$ROOT/lib/libtk8.6.dylib" \
  "$ROOT/lib/libtcl8.6.dylib" \
  "$ROOT/lib/tk9.0" \
  "$ROOT/lib/tk8.6" \
  "$ROOT/lib/tcl9" \
  "$ROOT/lib/tcl9.0" \
  "$ROOT/lib/tcl8" \
  "$ROOT/lib/tcl8.6" \
  "$ROOT/lib/itcl4.3.5" \
  "$ROOT/lib/tdbc1.1.12" \
  "$ROOT/lib/thread3.0.4" \
  "$ROOT/lib/python3.12/lib-dynload/_tkinter.cpython-312-darwin.so" \
  "$ROOT/lib/python3.12/tkinter" \
  "$ROOT/lib/python3.12/idlelib" \
  "$ROOT/lib/python3.12/turtledemo" \
  "$ROOT/lib/python3.12/site-packages/PIL/_imagingtk.cpython-312-darwin.so" \
  "$ROOT/lib/python3.12/site-packages/PIL/ImageTk.py" \
  "$ROOT/lib/python3.12/site-packages/PIL/_imagingtk.pyi"

# Any leftover Tk/Tcl dylibs or _tkinter modules
while IFS= read -r -d '' f; do
  drop "$f"
done < <(find "$ROOT" \( \
  -name 'libtcl*' -o -name 'libtk*' -o -name '*_tkinter*' -o -name 'libtcl9thread*' \
  \) -print0 2>/dev/null)

echo "note: stripped $removed Tcl/Tk paths from $ROOT"
