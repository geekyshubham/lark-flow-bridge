#!/bin/bash
set -euo pipefail
LARK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LARK_ICONSET="$LARK_ROOT/assets/AppIcon.iconset"
mkdir -p "$LARK_ICONSET"
for LARK_SIZE in 16 32 128 256 512; do
  sips -z "$LARK_SIZE" "$LARK_SIZE" "$LARK_ROOT/assets/app-icon.png" \
    --out "$LARK_ICONSET/icon_${LARK_SIZE}x${LARK_SIZE}.png" >/dev/null
  LARK_RETINA=$((LARK_SIZE * 2))
  sips -z "$LARK_RETINA" "$LARK_RETINA" "$LARK_ROOT/assets/app-icon.png" \
    --out "$LARK_ICONSET/icon_${LARK_SIZE}x${LARK_SIZE}@2x.png" >/dev/null
done
iconutil --convert icns "$LARK_ICONSET" --output "$LARK_ROOT/assets/AppIcon.icns"
printf 'Created %s\n' "$LARK_ROOT/assets/AppIcon.icns"
