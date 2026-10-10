#!/bin/zsh
# Ships the version in Tapestry/Info.plist: builds the app, signs it with the Developer ID,
# packages it as a drag-to-Applications disk image, notarizes and staples the image, and
# publishes build/Tapestry.dmg as a GitHub release.
#
#     scripts/release.sh "What changed, in a sentence or two."
#
# Bump CFBundleShortVersionString and CFBundleVersion in Tapestry/Info.plist and commit first.
#
# One-time setup on a new Mac:
#   - The HMDFV Inc. Developer ID Application certificate must be in the login keychain, and a
#     notarytool profile named "ramihmd-notary" must exist:
#     `xcrun notarytool store-credentials ramihmd-notary --apple-id <id> --team-id 8Z6WRF99H5`
set -euo pipefail

repo=HMDRAMS-DEV/tapestry
identity="Developer ID Application: HMDFV Inc. (8Z6WRF99H5)"
notary=ramihmd-notary

cd "$(dirname "$0")/.."
notes="${1:?Usage: scripts/release.sh \"release notes\"}"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Tapestry/Info.plist)
tag="v$version"
app=build/Tapestry.app
dmg=build/Tapestry.dmg
stage=build/dmg

[[ -z $(git status --porcelain) ]] || { echo "Commit or stash your changes first."; exit 1; }
if gh release view "$tag" -R "$repo" >/dev/null 2>&1; then echo "$tag is already released."; exit 1; fi

./build.sh
# Replace the local signature with the Developer ID, the hardened runtime, and a secure timestamp.
codesign --force --timestamp --options runtime --sign "$identity" --identifier dev.tapestry.Tapestry "$app"
codesign --verify --strict "$app"

# Notarizing the signed image covers the app inside it. Stapling the image lets it open offline.
rm -rf "$stage" "$dmg"
mkdir -p "$stage"
ditto "$app" "$stage/Tapestry.app"
ln -s /Applications "$stage/Applications"
hdiutil create -srcfolder "$stage" -volname Tapestry -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$dmg" -quiet
rm -rf "$stage"
codesign --force --timestamp --sign "$identity" "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$notary" --wait
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature "$dmg"

gh release create "$tag" "$dmg" -R "$repo" --target main --title "Tapestry $version" --notes "$notes"
echo "Released Tapestry $version: https://github.com/$repo/releases/tag/$tag"
