#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' resources/Info.plist)
package="OpenGame-${version}-launcher-preview-macos-arm64"
mkdir -p "dist/$package"
ditto build/OpenGame.app "dist/$package/OpenGame.app"
cp README.md LICENSE docs/DISTRIBUTION.md "dist/$package/"
ditto -c -k --sequesterRsrc --keepParent "dist/$package" "dist/$package.zip"
(cd dist && shasum -a 256 "$package.zip" > SHA256SUMS.txt)
