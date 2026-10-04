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
# macOS forgets the permission. A local certificate named "Tapestry Local Signing" keeps it stable.
identity=-
security find-identity -p codesigning | grep -q '"Tapestry Local Signing"' && identity="Tapestry Local Signing"
codesign --force --sign "$identity" --identifier dev.tapestry.Tapestry "$app"
echo "built $app"
