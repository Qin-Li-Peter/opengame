#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/OpenGame.iconset
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" resources/AppIcon.png --out "build/OpenGame.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" resources/AppIcon.png --out "build/OpenGame.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/OpenGame.iconset -o build/OpenGame.icns
