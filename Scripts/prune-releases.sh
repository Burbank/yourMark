#!/bin/bash
# Keep the two newest GitHub releases. Delete anything older.
set -euo pipefail
KEEP="${KEEP:-2}"
gh release list --limit 100 --json tagName,isDraft,publishedAt \
  --jq "sort_by(.publishedAt) | reverse | map(select(.isDraft|not)) | .[$KEEP:][].tagName" \
| while IFS= read -r tag; do
    [ -z "$tag" ] && continue
    echo "Deleting $tag"
    gh release delete "$tag" --yes --cleanup-tag
  done
echo "Kept the newest $KEEP releases."
