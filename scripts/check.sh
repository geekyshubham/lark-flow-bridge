#!/bin/bash
set -euo pipefail
LARK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LARK_APP="$LARK_ROOT/build/LARK Flow Bridge.app"
LARK_BINARY="$LARK_APP/Contents/MacOS/LARKFlowBridge"
[[ -x "$LARK_BINARY" ]] || { printf 'Run scripts/build.sh --universal first.\n' >&2; exit 1; }
codesign --verify --deep --strict "$LARK_APP"
plutil -lint "$LARK_APP/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$LARK_APP/Contents/Info.plist")" == AppIcon ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LARK_APP/Contents/Info.plist")" == io.github.geekyshubham.lark-flow-bridge ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$LARK_APP/Contents/Info.plist")" == "$(tr -d '[:space:]' < "$LARK_ROOT/VERSION")" ]]
[[ -s "$LARK_APP/Contents/Resources/AppIcon.icns" ]]
lipo "$LARK_BINARY" -verify_arch arm64 x86_64
for LARK_SCRIPT in "$LARK_ROOT"/scripts/*.sh; do bash -n "$LARK_SCRIPT"; done
printf 'App bundle, icon, signatures, universal architectures, and shell syntax verified.\n'
printf 'Physical receiver and Flow recording tests require a Mac with the LARK A2 connected.\n'
