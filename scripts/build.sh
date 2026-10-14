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
"$CC" tests/diagnostics/d3d12-clear.c -O2 -Wall -Wextra -Werror -ld3d12 -ldxguid -o "$APP/Contents/Resources/OpenGameD3D12Probe.exe"
"$CC" tests/diagnostics/dlss.c -O2 -Wall -Wextra -Werror -ld3d11 -o "$APP/Contents/Resources/OpenGameDLSSProbe.exe"
"$CC" tests/diagnostics/graphics-capabilities.c -O2 -Wall -Wextra -Werror -ld3d11 -o "$APP/Contents/Resources/OpenGameGraphicsProbe.exe"
"$CC" source/OpenGameNoOp.c -municode -O2 -Wall -Wextra -Werror -static -mwindows -o "$APP/Contents/Resources/steamerrorreporter64.exe"
"$CC" source/steam-wrapper/wrapper.c -municode -O2 -Wall -Wextra -static -mwindows -lshell32 -o "$APP/Contents/Resources/steamwebhelper.exe"
"$CC" source/pointer-input/input.c source/pointer-input/version.def -O2 -Wall -Wextra -Werror -shared -luser32 -lkernel32 -o "$APP/Contents/Resources/PointerInput/version.dll"
xcrun swiftc -sdk "${OG_SWIFT_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path "$PWD/build/module-cache" -target arm64-apple-macosx14.0 -swift-version 5 -O -whole-module-optimization -warnings-as-errors -parse-as-library source/OpenGameCore.swift source/OpenGame.swift -o "$APP/Contents/MacOS/OpenGame" -framework SwiftUI -framework AppKit
xcrun swiftc -sdk "${OG_SWIFT_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path "$PWD/build/module-cache" -target arm64-apple-macosx14.0 -swift-version 5 -O -whole-module-optimization -warnings-as-errors -parse-as-library source/OpenGameCore.swift source/OpenGameCLI.swift -o "$APP/Contents/MacOS/OpenGameCLI" -framework AppKit
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp -R licenses "$APP/Contents/Resources/Licenses"
cp -R recipes "$APP/Contents/Resources/Recipes"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP (launcher only; Wine runtimes are separate)"
