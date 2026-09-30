#!/bin/bash
set -euo pipefail
LARK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$LARK_ROOT/scripts/build.sh" --universal
mkdir -p "$LARK_ROOT/dist"
LARK_ZIP="$LARK_ROOT/dist/LARK-Flow-Bridge-macOS-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$LARK_ROOT/build/LARK Flow Bridge.app" "$LARK_ZIP"
(
  cd "$LARK_ROOT/dist"
  shasum -a 256 "$(basename "$LARK_ZIP")" > SHA256SUMS.txt
)
printf 'Release assets: %s\n' "$LARK_ROOT/dist"
