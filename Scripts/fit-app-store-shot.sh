#!/bin/zsh
# Fit an image inside 1280×800 without stretching. Pads the rest.
set -euo pipefail
SRC="${1:?image}"
DEST="${2:?destination jpg}"
PAD="${3:-1A2332}"

W=$(sips -g pixelWidth "$SRC" | awk '/pixelWidth/{print $2}')
H=$(sips -g pixelHeight "$SRC" | awk '/pixelHeight/{print $2}')
# Fit inside 1280×800
python3 - "$W" "$H" "$SRC" "$DEST" "$PAD" <<'PY'
import subprocess, sys, tempfile, os
w, h = int(sys.argv[1]), int(sys.argv[2])
src, dest, pad = sys.argv[3], sys.argv[4], sys.argv[5]
tw, th = 1280, 800
scale = min(tw / w, th / h)
nw, nh = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
tmp = dest + ".tmp.jpg"
subprocess.check_call(["sips", "-z", str(nh), str(nw), src, "--out", tmp], stdout=subprocess.DEVNULL)
subprocess.check_call(
    ["sips", "--padToHeightWidth", str(th), str(tw), "--padColor", pad, tmp, "--out", dest],
    stdout=subprocess.DEVNULL,
)
os.remove(tmp)
print(f"{os.path.basename(dest)}  {nw}×{nh} on 1280×800")
PY
