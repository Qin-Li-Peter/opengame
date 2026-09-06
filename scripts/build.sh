#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CC="${OG_MINGW_CC:-x86_64-w64-mingw32-gcc}"
command -v "$CC" >/dev/null || { echo 'Set OG_MINGW_CC to an LLVM-MinGW Windows x64 compiler.' >&2; exit 1; }
APP=build/OpenGame.app
rm -rf "$APP" build/OpenGame.iconset build/OpenGame.icns
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/PointerInput"
cp resources/Info.plist "$APP/Contents/Info.plist"
scripts/build-icon.sh
cp build/OpenGame.icns "$APP/Contents/Resources/OpenGame.icns"
"$CC" source/OpenGameWindow.c -municode -O2 -Wall -Wextra -Werror -static -mwindows -o "$APP/Contents/Resources/OpenGameWindow.exe"
"$CC" source/steam-wrapper/wrapper.c -municode -O2 -Wall -Wextra -static -mwindows -lshell32 -o "$APP/Contents/Resources/steamwebhelper.exe"
"$CC" source/pointer-input/input.c source/pointer-input/version.def -O2 -Wall -Wextra -Werror -shared -luser32 -lkernel32 -o "$APP/Contents/Resources/PointerInput/version.dll"
xcrun swiftc -target arm64-apple-macosx14.0 -swift-version 5 -warnings-as-errors -parse-as-library source/OpenGameCore.swift source/OpenGame.swift -o "$APP/Contents/MacOS/OpenGame" -framework SwiftUI -framework AppKit
xcrun swiftc -target arm64-apple-macosx14.0 -swift-version 5 -warnings-as-errors -parse-as-library source/OpenGameCore.swift source/OpenGameCLI.swift -o "$APP/Contents/MacOS/OpenGameCLI" -framework AppKit
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp -R licenses "$APP/Contents/Resources/Licenses"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP (launcher only; Wine runtimes are separate)"
