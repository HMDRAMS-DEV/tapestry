#!/bin/bash
# Compiles Tapestry.app into build/ with the Command Line Tools. No Xcode project.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$here/build/Tapestry.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$here/Tapestry/Info.plist" "$app/Contents/Info.plist"
iconutil -c icns "$here/Tapestry/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"

sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
xcrun swiftc -O -sdk "$sdk" -parse-as-library -swift-version 6 -target arm64-apple-macos15.0 \
    -module-name Tapestry -o "$app/Contents/MacOS/Tapestry" \
    $(find "$here/Tapestry" -name '*.swift')

# Accessibility permission is tied to the signature. An ad-hoc signature changes on every build, so
# macOS forgets the permission. The Developer ID matches release builds, so both share one grant.
# Without it, a local certificate named "Tapestry Local Signing" keeps the signature stable.
identity=-
identities="$(security find-identity -p codesigning)"
if grep -q '"Developer ID Application: HMDFV Inc. (8Z6WRF99H5)"' <<<"$identities"; then
    identity="Developer ID Application: HMDFV Inc. (8Z6WRF99H5)"
elif grep -q '"Tapestry Local Signing"' <<<"$identities"; then
    identity="Tapestry Local Signing"
fi
codesign --force --sign "$identity" --identifier dev.tapestry.Tapestry "$app"
echo "built $app"
