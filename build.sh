#!/bin/bash
# Compiles Optap.app into build/ with the Command Line Tools. No Xcode project.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$here/build/Optap.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$here/Optap/Info.plist" "$app/Contents/Info.plist"
iconutil -c icns "$here/Optap/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"

sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
xcrun swiftc -O -sdk "$sdk" -parse-as-library -swift-version 6 -target arm64-apple-macos15.0 \
    -o "$app/Contents/MacOS/Optap" \
    $(find "$here/Optap" -name '*.swift')

# Accessibility permission is tied to the signature. An ad-hoc signature changes on every build, so
# macOS forgets the permission. A local certificate named "Optap Local Signing" keeps it stable.
identity=-
security find-identity -p codesigning | grep -q '"Optap Local Signing"' && identity="Optap Local Signing"
codesign --force --sign "$identity" --identifier dev.optap.Optap "$app"
echo "built $app"
