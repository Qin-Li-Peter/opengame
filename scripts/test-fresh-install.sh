#!/bin/bash
set -euo pipefail
app=${1:-build/OpenGame.app}
cli="$app/Contents/MacOS/OpenGameCLI"
test -x "$cli" || { echo "Missing OpenGameCLI in $app" >&2; exit 1; }
test -x "$app/Contents/Resources/Runtime/Engines/WineFOSS11/bin/wine" || { echo "App does not contain a runtime" >&2; exit 1; }
runtime="$app/Contents/Resources/Runtime"
gst="$runtime/Engines/Support/GStreamer.framework/Versions/1.0"
test -f "$runtime/Engines/WineFOSS11/lib/wine/x86_64-unix/winegstreamer.so"
test -f "$runtime/Engines/WineFOSS11/lib/wine/x86_64-windows/winegstreamer.dll"
test -f "$runtime/Engines/WineFOSS11/lib/wine/i386-windows/winegstreamer.dll"
GST_PLUGIN_PATH="$gst/lib/gstreamer-1.0" \
GST_PLUGIN_SYSTEM_PATH="$gst/lib/gstreamer-1.0" \
DYLD_FALLBACK_LIBRARY_PATH="$gst/lib:/usr/lib" \
"$gst/bin/gst-inspect-1.0" decodebin >/dev/null
"$gst/bin/gst-inspect-1.0" vtdec >/dev/null
"$gst/bin/gst-launch-1.0" -q videotestsrc num-buffers=24 ! videoconvert ! openh264enc ! h264parse ! vtdec ! fakesink
if "$gst/bin/gst-inspect-1.0" x264enc >/dev/null 2>&1; then
  echo "GPL/restricted x264 plugin must not be present in the distributable runtime" >&2
  exit 1
fi

home=$(mktemp -d)
trap 'rm -rf "$home"' EXIT
root="$home/OpenGame"
status=$(OPENGAME_ROOT="$root" "$cli" runtime-status)
case "$status" in *"OpenGame.app"*"DXMT / DXVK"*) ;; *) echo "Unexpected runtime status: $status" >&2; exit 1;; esac
id=$(OPENGAME_ROOT="$root" "$cli" create "Fresh Install Test" dxmt foss)
prefix="$root/Prefixes/$id"
test -f "$prefix/.opengame-fonts"
test "$(find "$prefix/drive_c/windows/Fonts" -name 'Liberation*.ttf' | wc -l | tr -d ' ')" = 12
OPENGAME_ROOT="$root" "$cli" recipes | grep -q '^steam'
if test -n "${OG_MINGW_CC:-}"; then
  "$OG_MINGW_CC" docs/d3d12.c -O2 -Wall -Wextra -Werror -ld3d12 -ldxgi -o "$home/d3d12-smoke.exe"
  OPENGAME_ROOT="$root" "$cli" probe "$id" "$home/d3d12-smoke.exe"
  grep -q 'D3D12_CREATE_DEVICE=00000000' "$root/Logs/probe-$id-d3d12-smoke.exe.log"
  "$OG_MINGW_CC" docs/winegstreamer-smoke.c -O2 -Wall -Wextra -Werror -o "$home/winegstreamer-smoke64.exe"
  OPENGAME_ROOT="$root" "$cli" probe "$id" "$home/winegstreamer-smoke64.exe"
  grep -q 'WINEGSTREAMER_LOAD=OK' "$root/Logs/probe-$id-winegstreamer-smoke64.exe.log"
  mingw32="$(dirname "$OG_MINGW_CC")/i686-w64-mingw32-gcc"
  if test -x "$mingw32"; then
    "$mingw32" docs/winegstreamer-smoke.c -O2 -Wall -Wextra -Werror -o "$home/winegstreamer-smoke32.exe"
    OPENGAME_ROOT="$root" "$cli" probe "$id" "$home/winegstreamer-smoke32.exe"
    grep -q 'WINEGSTREAMER_LOAD=OK' "$root/Logs/probe-$id-winegstreamer-smoke32.exe.log"
  fi
fi
# Runtime creation was exercised above. Keep the archive phase small so CI
# tests archive semantics instead of spending minutes compressing Wine's stock C: tree.
find "$prefix" -mindepth 1 ! -name system.reg -exec rm -rf {} +
archive="$home/Fresh.opengamebottle"
OPENGAME_ROOT="$root" "$cli" export-bottle "$id" "$archive"
restored=$(OPENGAME_ROOT="$root" "$cli" import-bottle "$archive" "Restored Test")
OPENGAME_ROOT="$root" "$cli" list | grep -q "$restored"
test -f "$root/Prefixes/$restored/system.reg"
echo "PASS: bundled runtime, GStreamer discovery and Wine bridge, clean data root, bottle creation, fonts, recipes, D3D12 device probe, archive export and restore"
