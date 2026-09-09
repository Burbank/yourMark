#!/bin/bash
# Keep the newest GitHub release plus two older ones (three in total).
set -euo pipefail
KEEP="${KEEP:-3}"
gh release list --limit 100 --json tagName,isDraft,publishedAt \
  --jq "sort_by(.publishedAt) | reverse | map(select(.isDraft|not)) | .[$KEEP:][].tagName" \
| while IFS= read -r tag; do
    [ -z "$tag" ] && continue
    echo "Deleting $tag"
    gh release delete "$tag" --yes --cleanup-tag
  done
echo "Kept the newest $KEEP releases (current + two older)."
