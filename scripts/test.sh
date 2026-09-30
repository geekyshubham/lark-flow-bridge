#!/bin/bash
set -euo pipefail
LARK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LARK_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$LARK_TEST_DIR"' EXIT
sed '/^let app = NSApplication.shared/,$d' "$LARK_ROOT/LARKFlowBridge.swift" > "$LARK_TEST_DIR/main.swift"
cat "$LARK_ROOT/tests/receiver-status.swift" >> "$LARK_TEST_DIR/main.swift"
xcrun swiftc "$LARK_TEST_DIR/main.swift" -framework AppKit -framework ApplicationServices -framework IOKit -o "$LARK_TEST_DIR/status-tests"
"$LARK_TEST_DIR/status-tests"
