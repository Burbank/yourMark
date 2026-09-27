#!/bin/zsh
# Fail if the Store bundle still contains Apple's rejected Tk symbol
# or the CPython urllib "itms-services" scheme (Guideline 2.5.2).
set -euo pipefail
APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "usage: verify-no-private-api.sh <yourMark.app>" >&2
  exit 1
fi
hits=$(rg -a -l "NSWindowDidOrderOnScreenNotification|_NSWindowDidOrderOnScreenNotification" "$APP" 2>/dev/null || true)
if [[ -n "$hits" ]]; then
  echo "error: private API string still present:" >&2
  echo "$hits" >&2
  exit 1
fi
if [[ -e "$APP/Contents/Resources/python/lib/libtcl9tk9.0.dylib" || -e "$APP/Contents/Resources/python/lib/python3.12/lib-dynload/_tkinter.cpython-312-darwin.so" ]]; then
  echo "error: Tcl/Tk is still inside the app" >&2
  exit 1
fi
itms=$(rg -a -l "itms-services" "$APP" 2>/dev/null || true)
if [[ -n "$itms" ]]; then
  echo "error: itms-services is still inside the app (Guideline 2.5.2):" >&2
  echo "$itms" >&2
  exit 1
fi
echo "ok: no _NSWindowDidOrderOnScreenNotification, no bundled Tk, no itms-services"
