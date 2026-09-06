#!/bin/bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
app=${1:?usage: embed-runtime.sh APP RUNTIME_ROOT}
runtime_root=${2:?usage: embed-runtime.sh APP RUNTIME_ROOT}
resources="$app/Contents/Resources"
payload="$resources/Runtime"

test -x "$runtime_root/Engines/WineFOSS11/bin/wine" || { echo "Missing WineFOSS11 in $runtime_root" >&2; exit 1; }
for renderer in DXMT DXVK; do
  test -d "$runtime_root/Engines/WineFOSS11-$renderer/lib/wine" || { echo "Missing WineFOSS11-$renderer" >&2; exit 1; }
done

rm -rf "$payload"
mkdir -p "$payload/Engines" "$payload/RendererPacks/dxmt" "$payload/RendererPacks/dxvk"
ditto "$runtime_root/Engines/WineFOSS11" "$payload/Engines/WineFOSS11"
if test -d "$runtime_root/Engines/Support"; then
  ditto "$runtime_root/Engines/Support" "$payload/Engines/Support"
fi

for renderer in dxmt dxvk; do
  case "$renderer" in
    dxmt) variant="$runtime_root/Engines/WineFOSS11-DXMT/lib/wine" ;;
    dxvk) variant="$runtime_root/Engines/WineFOSS11-DXVK/lib/wine" ;;
  esac
  for arch in x86_64-windows i386-windows; do
    mkdir -p "$payload/RendererPacks/$renderer/$arch"
    for dll in d3d10core.dll d3d11.dll dxgi.dll; do
      test -f "$variant/$arch/$dll" || { echo "Missing $variant/$arch/$dll" >&2; exit 1; }
      cp -p "$variant/$arch/$dll" "$payload/RendererPacks/$renderer/$arch/$dll"
    done
  done
done

cp "$repo/runtime/manifest.json" "$payload/manifest.json"
cp "$repo/docs/provenance.json" "$payload/provenance.json"
xattr -cr "$payload" 2>/dev/null || true
"$repo/scripts/relocate-runtime.py" "$payload"
"$repo/scripts/audit-runtime.py" "$payload"
echo "Embedded deduplicated runtime in $app"
