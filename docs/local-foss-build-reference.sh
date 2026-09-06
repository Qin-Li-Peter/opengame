# HISTORICAL RECIPE ONLY: see docs/RUNTIME.md for required inputs.
#!/bin/zsh
# Local research build. Requires the verified archives and toolchain in work/.
# It does not replace any installed OpenGame runtime or CrossOver component.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
repository="$(cd "$here/.." && pwd)"
workspace="${OG_BUILD_WORKSPACE:-$repository}"
cd "$workspace"
python3 - <<'PY'
from pathlib import Path
import shutil,subprocess
root=Path.cwd();source=Path.home()/'Library/Application Support/OpenGame/Engines/WineHQ11/lib';dest=root/'work/cx-deps/lib'
if dest.is_symlink():
 assert dest.resolve()==source.resolve();dest.unlink()
dest.mkdir(parents=True,exist_ok=True)
for f in source.iterdir():
 if f.is_dir():continue
 target=dest/f.name
 if not target.exists():target.symlink_to(f)
target=dest/'libfreetype.dylib'
if target.is_symlink():target.unlink();shutil.copy2((source/'libfreetype.dylib').resolve(),target)
subprocess.run(['install_name_tool','-id','@rpath/libfreetype.dylib',str(target)],check=True)
subprocess.run(['codesign','--force','--sign','-',str(target)],check=True)
# GnuTLS headers come from the same verified public FOSS archive.
headers=next((root/'work/crossover-foss/sources/gnutls').rglob('gnutls.h.in')).parent
include=root/'work/cx-deps/include/gnutls';include.mkdir(parents=True,exist_ok=True)
for h in headers.glob('*.h'):shutil.copy2(h,include/h.name)
text=(headers/'gnutls.h.in').read_text()
for k,v in {'VERSION':'3.8.3','MAJOR_VERSION':'3','MINOR_VERSION':'8','PATCH_VERSION':'3','NUMBER_VERSION':'0x030803','DEFINE_IOVEC_T':'#include <sys/uio.h>\ntypedef struct iovec giovec_t;'}.items():text=text.replace('@'+k+'@',v)
(include/'gnutls.h').write_text(text)
tls=dest/'libgnutls.30.dylib'
if tls.is_symlink():tls.unlink()
shutil.copy2((source/'libgnutls.30.dylib').resolve(),tls)
subprocess.run(['install_name_tool','-id','@rpath/libgnutls.30.dylib',str(tls)],check=True)
subprocess.run(['codesign','--force','--sign','-',str(tls)],check=True)
link=dest/'libgnutls.dylib'
if link.exists() or link.is_symlink():link.unlink()
link.symlink_to(tls.name)
PY
gst_sdk="$workspace/work/gst-sdk-1.28.1"
test -f "$gst_sdk/lib/pkgconfig/gstreamer-1.0.pc" || { echo "Missing merged GStreamer 1.28.1 SDK: $gst_sdk" >&2; exit 1; }
export PATH="$workspace/work/toolchains/llvm-mingw-20260826-ucrt-macos-universal/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PKG_CONFIG=/opt/homebrew/bin/pkg-config
export PKG_CONFIG_PATH="$gst_sdk/lib/pkgconfig"
mkdir -p work/cx-wine-gst-build
cd work/cx-wine-gst-build
../crossover-foss/sources/wine/configure \
 --host=x86_64-apple-darwin --enable-archs=x86_64,i386 --with-mingw=llvm-mingw \
 --without-x --disable-tests --prefix="$workspace/work/cx-wine-gst-stage" \
 CC='/usr/bin/clang -arch x86_64' CXX='/usr/bin/clang++ -arch x86_64' \
 OBJC='/usr/bin/clang -arch x86_64' BISON=/opt/homebrew/opt/bison/bin/bison \
 GNUTLS_CFLAGS="-I$workspace/work/cx-deps/include" \
 GNUTLS_LIBS="-L$workspace/work/cx-deps/lib -lgnutls" \
 FREETYPE_CFLAGS='-I/opt/homebrew/include/freetype2' \
 FREETYPE_LIBS="-L$workspace/work/cx-deps/lib -lfreetype" \
 LDFLAGS="-L$workspace/work/cx-deps/lib -L$gst_sdk/lib -Wl,-rpath,$workspace/work/cx-deps/lib -Wl,-rpath,$gst_sdk/lib -Wl,-headerpad_max_install_names" \
 > ../cx-wine-gst-configure.log 2>&1
grep 'gst_pad_new in -lgstreamer-1.0... yes' ../cx-wine-gst-configure.log
make -j6 >> ../cx-wine-gst-build.log 2>&1
make -j6 install >> ../cx-wine-gst-install.log 2>&1
test -f "$workspace/work/cx-wine-gst-stage/lib/wine/x86_64-unix/winegstreamer.so"
test -f "$workspace/work/cx-wine-gst-stage/lib/wine/x86_64-windows/winegstreamer.dll"
test -f "$workspace/work/cx-wine-gst-stage/lib/wine/i386-windows/winegstreamer.dll"
