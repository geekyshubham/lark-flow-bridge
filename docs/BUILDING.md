# Build, verify, and release LARK Flow Bridge

## Build prerequisites

- A Mac with a macOS SDK and Swift 5.7+ from Xcode or Xcode Command Line Tools.
- macOS tools: `xcrun`, `swiftc`, `lipo`, `codesign`, `plutil`, `sips`, `iconutil`, `ditto`, and `shasum`.
- Git to clone the source. GitHub CLI is optional and used only to publish a release.

No package-manager or runtime dependencies are required. For the downloaded app, a compiler is not required.

```sh
xcode-select --install
git clone https://github.com/geekyshubham/lark-flow-bridge.git
cd lark-flow-bridge
./scripts/package.sh
./scripts/check.sh
```

`package.sh` builds macOS 13+ binaries for both `arm64` and `x86_64`, creates a universal executable, embeds `AppIcon.icns`, signs the bundle ad hoc, and creates a ZIP and checksum. The source uses Apple frameworks available on the targeted macOS versions; physical runtime testing is limited to the setup documented in the README.

The public bundle identifier is `io.github.geekyshubham.lark-flow-bridge`. Accessibility permissions belong to the installed app identity and must be granted on each user's Mac.

## Icon assets

`assets/app-icon-source.png` is the original generated artwork. `assets/app-icon.png` is its 1024-pixel app asset. `assets/AppIcon.icns` contains the standard macOS icon resolutions. Regenerate ICNS with:

```sh
./scripts/make-icon.sh
```

Builds use the normal bundled icon through `CFBundleIconFile`. Applying a Finder custom icon to a signed app can add resource-fork metadata that fails strict bundle verification, so this project embeds the icon before signing. Updating the signed bundle can require a fresh Accessibility grant.

## Release checklist

1. Set `VERSION` and update `CHANGELOG.md`.
2. Run `scripts/package.sh` and `scripts/check.sh` on macOS.
3. Verify the app UI and icon. Test real receiver clicks, restoration, and Flow start/stop on available hardware.
4. Commit the source, icon, and documentation. Confirm the build workflow succeeds.
5. Create a GitHub release and upload the ZIP plus `SHA256SUMS.txt`.

For maintainers using GitHub CLI:

```sh
gh release create "v$(cat VERSION)" \
  dist/LARK-Flow-Bridge-macOS-universal.zip dist/SHA256SUMS.txt \
  --title "LARK Flow Bridge $(cat VERSION)" --notes-file RELEASE_NOTES.md
```

## Optional Developer ID signing and notarization

The default release is ad hoc signed and not notarized. Maintainers who have an Apple Developer ID Application certificate can sign the completed app using their own identity:

```sh
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  "build/LARK Flow Bridge.app"
codesign --verify --deep --strict "build/LARK Flow Bridge.app"
ditto -c -k --sequesterRsrc --keepParent \
  "build/LARK Flow Bridge.app" dist/LARK-Flow-Bridge-macOS-universal.zip
xcrun notarytool submit dist/LARK-Flow-Bridge-macOS-universal.zip \
  --keychain-profile YOUR_NOTARY_PROFILE --wait
xcrun stapler staple "build/LARK Flow Bridge.app"
```

Repackage after stapling and regenerate the checksum. Keep signing identities and notarization credentials out of the repository. Use Apple's [notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
