# Building and distributing the runtime

OpenGame full packages use a Wine FOSS base core, a complete matching DXMT core, and a small DXVK renderer pack. DXMT's Unix-side Metal bridge and Wine build must remain together; treating it as only three Windows DLLs caused launch-order-dependent D3D11 initialization failures. The packager therefore accepts the extra size and audits both complete cores.

## Inputs

All inputs must be acquired from their publishers and verified with `components.json`. The current runtime was built from CodeWeavers' public CrossOver 26.3.0 FOSS archive, DXMT 0.80, GStreamer 1.28.1, and the LLVM-MinGW toolchain recorded in the repository. `scripts/fetch-sources.sh` downloads the corresponding source archives. The matching official GStreamer development package and its SHA-256 are also recorded as a build dependency. Do not use files from `CrossOver.app`; its proprietary launcher, recipes, compatibility database, and D3DMetal are outside this build.

The current research build command is preserved in `docs/local-foss-build-reference.sh`. It documents the exact configure switches used for the verified core, including the matching GStreamer 1.28.1 SDK needed to build `winegstreamer`. The dependency SDK still needs a clean automated build before CI can compile the entire runtime from zero. Until that job is complete, release maintainers must stage a previously audited runtime and publish the corresponding source archive beside every binary release.

The GStreamer SDK is assembled outside the repository so its 4+ GB development tree is never committed. Download both official 1.28.1 packages recorded in `components.json`, verify their hashes, expand them with `pkgutil --expand-full`, and merge every component `Payload` into `work/gst-sdk-1.28.1`. The development package supplies headers and pkg-config files. Set `OG_BUILD_WORKSPACE` to the directory containing this `work` tree before running `docs/local-foss-build-reference.sh`.

For the distributable playback runtime, expand the official runtime package and run `scripts/stage-gstreamer-runtime.sh EXPANDED_PKG RUNTIME_ROOT`. This script uses `runtime/gstreamer-components.txt` as an allowlist and refuses known GPL/restricted plugin files. The selected runtime still includes OpenH264 and Apple VideoToolbox, which the fresh-install test uses for an actual H.264 pipeline. Source packaging also parses every GStreamer `subprojects/*.wrap`, downloads each pinned archive, verifies its upstream hash, and includes the resulting source set with the release.

## Local Wine patches

Apply `scripts/apply-wine-patches.sh WINE_SOURCE_DIRECTORY` before building either core. The historical build recipe now includes this step. Version 0.5.5 requires `runtime/patches/darwin-ip-recvtos.patch`; prebuilt runtimes from older releases do not contain the fix. Compile and run `tests/diagnostics/udp-tos.c` against every staged core before packaging. See `docs/STEAM-NETWORK-FREEZE.md` for the failure and validation.

## Full package

```sh
scripts/build.sh
scripts/package-full.sh "$HOME/Library/Application Support/OpenGame"
```

The command audits symlinks, user data, absolute Mach-O dependencies, and renderer pack completeness. It creates a full app archive and a separate corresponding-source archive in `dist/`.

For Developer ID distribution, set `OG_CODESIGN_IDENTITY`, package, and then submit the ZIP with `scripts/notarize.sh`. Notarization requires the repository owner's Apple Developer credentials and cannot be completed by source code alone.
