#!/bin/bash
set -euo pipefail
archive=${1:?usage: notarize.sh ZIP KEYCHAIN_PROFILE}
profile=${2:?usage: notarize.sh ZIP KEYCHAIN_PROFILE}
xcrun notarytool submit "$archive" --keychain-profile "$profile" --wait
app_name=$(zipinfo -1 "$archive" | awk -F/ '/\.app\/$/{print $1"/"$2; exit}')
test -n "$app_name" || { echo 'No app bundle found in archive' >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ditto -x -k "$archive" "$tmp"
xcrun stapler staple "$tmp/$app_name"
xcrun stapler validate "$tmp/$app_name"
ditto -c -k --sequesterRsrc --keepParent "$tmp/${app_name%%/*}" "$archive"
