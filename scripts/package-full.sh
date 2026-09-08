#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

runtime_root=${1:?usage: package-full.sh RUNTIME_ROOT [SOURCE_DIRECTORY]}
source_directory=${2:-build/sources}
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' resources/Info.plist)
package="OpenGame-${version}-macos-arm64"
source_package="OpenGame-${version}-corresponding-source"

scripts/fetch-sources.sh "$source_directory"

rm -rf "dist/$package" "dist/$package.zip" "dist/$source_package" "dist/$source_package.tar.xz"
mkdir -p "dist/$package" "dist/$source_package/upstream"
ditto build/OpenGame.app "dist/$package/OpenGame.app"
scripts/embed-runtime.sh "dist/$package/OpenGame.app" "$runtime_root"
scripts/install-font-pack.sh "dist/$package/OpenGame.app/Contents/Resources/Runtime" "$source_directory"
scripts/audit-runtime.py "dist/$package/OpenGame.app/Contents/Resources/Runtime"
cp README.md CHANGELOG.md LICENSE docs/DISTRIBUTION.md docs/THIRD_PARTY.md docs/FRIENDS.md "dist/$package/"

scripts/sign-app.sh "dist/$package/OpenGame.app" "${OG_CODESIGN_IDENTITY:--}"
codesign --verify --deep --strict "dist/$package/OpenGame.app"

git archive --format=tar HEAD | tar -xf - -C "dist/$source_package"
find "$source_directory" -maxdepth 1 -type f -exec cp {} "dist/$source_package/upstream/" \;
if test -d "$source_directory/gstreamer-subprojects"; then
  cp -R "$source_directory/gstreamer-subprojects" "dist/$source_package/upstream/"
fi
cp runtime/BUILDING.md "dist/$source_package/BUILDING-RUNTIME.md"

ditto -c -k --sequesterRsrc --keepParent "dist/$package" "dist/$package.zip"
tar -cJf "dist/$source_package.tar.xz" -C dist "$source_package"
(cd dist && shasum -a 256 "$package.zip" "$source_package.tar.xz" > SHA256SUMS.txt)
echo "Created dist/$package.zip and dist/$source_package.tar.xz"
