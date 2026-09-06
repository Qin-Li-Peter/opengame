#!/bin/bash
set -euo pipefail
app=${1:?usage: sign-app.sh APP 'Developer ID Application: Name (TEAMID)'}
identity=${2:?usage: sign-app.sh APP 'Developer ID Application: Name (TEAMID)'}
repo=$(cd "$(dirname "$0")/.." && pwd)

sign_library() {
  if test "$identity" = -; then
    codesign --force --sign - "$1"
  else
    codesign --force --timestamp --options runtime --sign "$identity" "$1"
  fi
}

sign_executable() {
  if test "$identity" = -; then
    codesign --force --entitlements "$repo/resources/OpenGame.entitlements" --sign - "$1"
  else
    codesign --force --timestamp --options runtime --entitlements "$repo/resources/OpenGame.entitlements" --sign "$identity" "$1"
  fi
}

# Wine generates and loads executable code at runtime. These entitlements are
# applied to the outer app and all bundled Mach-O code for Developer ID builds.
find "$app/Contents/Resources/Runtime" -type f -print0 2>/dev/null | while IFS= read -r -d '' file; do
  if file "$file" | grep -q 'Mach-O'; then
    sign_library "$file"
  fi
done
sign_executable "$app/Contents/MacOS/OpenGameCLI"
sign_executable "$app/Contents/MacOS/OpenGame"
sign_executable "$app"
codesign --verify --deep --strict --verbose=2 "$app"
