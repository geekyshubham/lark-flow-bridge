#!/bin/bash
set -euo pipefail
LARK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LARK_VERSION="$(tr -d '[:space:]' < "$LARK_ROOT/VERSION")"
LARK_BUNDLE_ID="io.github.geekyshubham.lark-flow-bridge"
LARK_OUTPUT="$LARK_ROOT/build"
LARK_UNIVERSAL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --universal) LARK_UNIVERSAL=1; shift ;;
    --output) LARK_OUTPUT="$2"; shift 2 ;;
    --help)
      printf 'Usage: scripts/build.sh [--universal] [--output DIRECTORY]\n'
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ "$(uname -s)" == Darwin ]] || { printf 'Build on macOS with Xcode Command Line Tools.\n' >&2; exit 1; }
xcrun --find swiftc >/dev/null
LARK_SDK="$(xcrun --sdk macosx --show-sdk-path)"
LARK_APP="$LARK_OUTPUT/LARK Flow Bridge.app"
mkdir -p "$LARK_APP/Contents/MacOS" "$LARK_APP/Contents/Resources"
if [[ ! -f "$LARK_ROOT/assets/AppIcon.icns" ]]; then "$LARK_ROOT/scripts/make-icon.sh"; fi
cp "$LARK_ROOT/assets/AppIcon.icns" "$LARK_APP/Contents/Resources/AppIcon.icns"
LARK_NATIVE_ARCH="$(uname -m)"
LARK_ARCHS=("$LARK_NATIVE_ARCH")
if [[ "$LARK_UNIVERSAL" == 1 ]]; then LARK_ARCHS=(arm64 x86_64); fi
for LARK_ARCH in "${LARK_ARCHS[@]}"; do
  xcrun swiftc "$LARK_ROOT/LARKFlowBridge.swift" -O -sdk "$LARK_SDK" \
    -target "${LARK_ARCH}-apple-macosx13.0" \
    -framework AppKit -framework ApplicationServices -framework IOKit \
    -o "$LARK_OUTPUT/LARKFlowBridge-$LARK_ARCH"
done
if [[ "$LARK_UNIVERSAL" == 1 ]]; then
  lipo -create "$LARK_OUTPUT/LARKFlowBridge-arm64" "$LARK_OUTPUT/LARKFlowBridge-x86_64" \
    -output "$LARK_APP/Contents/MacOS/LARKFlowBridge"
else
  cp "$LARK_OUTPUT/LARKFlowBridge-$LARK_NATIVE_ARCH" "$LARK_APP/Contents/MacOS/LARKFlowBridge"
fi
cat > "$LARK_APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$LARK_BUNDLE_ID</string>
<key>CFBundleName</key><string>LARK Flow Bridge</string>
<key>CFBundleDisplayName</key><string>LARK Flow Bridge</string>
<key>CFBundleExecutable</key><string>LARKFlowBridge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$LARK_VERSION</string>
<key>CFBundleVersion</key><string>$LARK_VERSION</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSUIElement</key><false/>
</dict></plist>
EOF
plutil -lint "$LARK_APP/Contents/Info.plist" >/dev/null
codesign --force --sign - "$LARK_APP"
codesign --verify --deep --strict "$LARK_APP"
printf 'Built %s (%s)\n' "$LARK_APP" "$(lipo -archs "$LARK_APP/Contents/MacOS/LARKFlowBridge")"
