# Contributing

Build and verify on macOS with `./scripts/package.sh` and `./scripts/check.sh` before opening a pull request. Use the bug-report template for hardware and permission failures, and include macOS, receiver firmware, app version, and the bridge's status message.

Changes to USB commands or click detection need testing on actual supported hardware. Do not infer compatibility with another LARK model from similar product names. Keep source and documentation aligned about permissions, recording state, polling, and noise-setting behavior.

The app should remain local and dependency-free. Do not include private transcripts, credentials, device serial numbers, or personal diagnostic logs in issues or commits.
