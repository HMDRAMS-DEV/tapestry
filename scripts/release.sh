#!/bin/zsh
# Ships the version in Tapestry/Info.plist: builds the app, signs it with the Developer ID,
# notarizes and staples it, and publishes build/Tapestry.zip as a GitHub release.
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
zip=build/Tapestry.zip

[[ -z $(git status --porcelain) ]] || { echo "Commit or stash your changes first."; exit 1; }
if gh release view "$tag" -R "$repo" >/dev/null 2>&1; then echo "$tag is already released."; exit 1; fi

./build.sh
# Replace the local signature with the Developer ID, the hardened runtime, and a secure timestamp.
codesign --force --timestamp --options runtime --sign "$identity" --identifier dev.tapestry.Tapestry "$app"
codesign --verify --strict "$app"

# notarytool takes a zip, but the ticket is stapled to the app, so zip it again afterwards.
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$notary" --wait
xcrun stapler staple "$app"
spctl --assess --type execute "$app"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

gh release create "$tag" "$zip" -R "$repo" --target main --title "Tapestry $version" --notes "$notes"
echo "Released Tapestry $version: https://github.com/$repo/releases/tag/$tag"
