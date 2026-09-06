#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

expanded=${1:?usage: stage-gstreamer-runtime.sh EXPANDED_GSTREAMER_PKG RUNTIME_ROOT}
runtime_root=${2:?usage: stage-gstreamer-runtime.sh EXPANDED_GSTREAMER_PKG RUNTIME_ROOT}
target="$runtime_root/Engines/Support/GStreamer.framework/Versions/1.0"
test -f "$expanded/Distribution" || { echo "Not an expanded GStreamer package: $expanded" >&2; exit 1; }
test ! -e "$target" || { echo "Refusing to merge over an existing GStreamer runtime: $target" >&2; exit 1; }
mkdir -p "$target"

while IFS= read -r package; do
  case "$package" in ''|'#'*) continue ;; esac
  payload="$expanded/$package/Payload"
  test -d "$payload" || { echo "Missing GStreamer component: $package" >&2; exit 1; }
  rsync -a "$payload"/ "$target"/
done < runtime/gstreamer-components.txt

cp "$expanded/Resources/license.txt" "$target/LICENSE-GSTREAMER.txt"
cp runtime/gstreamer-components.txt "$target/OPENGAME-COMPONENTS.txt"
test -x "$target/bin/gst-inspect-1.0"
test -f "$target/lib/gstreamer-1.0/libgstapplemedia.dylib"
test -f "$target/lib/gstreamer-1.0/libgstopenh264.dylib"
if find "$target" -iname '*x264*' -o -iname '*dvdread*' | grep -q .; then
  echo "A GPL/restricted plugin entered the playback runtime" >&2
  exit 1
fi
echo "Staged allowlisted GStreamer playback runtime in $target"
