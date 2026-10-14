# Steam idle CPU: one-byte BOOLEAN at the Wine syscall boundary

OpenGame 0.5.8 includes `ntdirectory-boolean-abi.patch`, built from the exact public CodeWeavers 26.3.0 FOSS archive recorded in `components.json`. It does not use proprietary CrossOver files.

## Diagnosis

On the test Mac, the launcher remained at 0.0% CPU while Steam's Wine server stayed near 48% and its CEF helper near 55–61% with no game or download running. Sampling located `NtQueryDirectoryObject` in a CEF foreground worker and `get_directory_entries` in the Wine server. The compatibility-file watcher had already exited, excluding that watcher as the observed continuing load.

A bounded numeric relay captured 500 Steam calls in 4.311 seconds: 1024-byte buffer, single-entry low byte 1, restart raw value `0x00140000` (low byte 0), and 499 captured success returns. A separate small-buffer probe found a different zero-progress path, but that path did not match Steam's actual parameters and was not patched.

Windows `BOOLEAN` is one byte. The original Unix implementation's optimized restart branch tested all 32 bits. A bounded x64 call bridge reproduced Steam's raw argument bits in an isolated prefix: restart 0 enumerated all five entries and terminated; restart `0x00140000` repeatedly returned the first entry with context 1→1 and the same fingerprint. The patch forces byte stores/loads for restart and single-entry flags while preserving the exported signature. Assembly inspection confirms byte comparison rather than the original full-width comparison.

The verified source archive SHA-256 is `ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872`. Its `sync.c:2095` and `directory.c:597` match the baseline sample locations. Candidate and baseline expose the same 290 public symbols.

## Build and regressions

Apply all `runtime/patches/*.patch` using `scripts/apply-wine-patches.sh`; retain the Darwin `IP_RECVTOS` patch. Build the matching x86_64 Unix `ntdll.so` in a separate source/build tree, then stage and sign a separate application. Do not overwrite a running module.

Use the tested macOS 26.5 SDK explicitly. An initial default-SDK-27 candidate enabled `HAVE_PIPE2`, then crashed at a null `pipe2` call on the macOS 26.6 test host. That failed candidate is excluded. The 26.5 candidate initialized successfully and passed the raw BOOLEAN regression, directory buffer-boundary diagnostic, UDP TOS `0xb8`, and thread/mutex/event/semaphore checks. No new third-party dylib dependency was introduced.

Run the portable regression against each staged core:

```sh
python3 scripts/test-ntdirectory-boolean.py /path/to/OpenGame.app --engine WineFOSS11-DXMT
python3 scripts/test-ntdirectory-boolean.py /path/to/OpenGame.app --engine WineFOSS11
```

The script compiles the x64 fixture, creates a fresh independent prefix, and retains results under `build/ntdirectory-validation`. Each NT call has a 1.5-second deadline, the fixture a 15-second watchdog, and initialization/test/cleanup have host deadlines. Only that new prefix's server is stopped. `--expect-normalized` fails if the raw-bit groups cannot advance and terminate.

## Validation limits

A subsequent 75-second actual-client check reduced Wine server CPU to 0.7–1.0%, versus the original sustained ~48%. CEF still used 37–39% CPU and approximately 1.5 GB RSS. A numeric recheck captured finite enumeration and end states; this is not an overall low-load or matched-scene performance claim. Steam returned a license package for App ID 4001890, but visible-client behavior and download remain unverified. Normal `-shutdown` did not complete within ten seconds; prefix-specific cleanup removed the diagnostic processes. Game ownership, download, private-room fishing, audio, save/reload and three full play cycles remain unverified. No game FPS, tail latency or CrossOver performance parity is established by these diagnostics.

The tested runtime Mach-O minimum OS was 26.0, despite the launcher's older deployment setting. This run verifies macOS 26.6 only; launcher settings alone do not prove support for macOS 14. New candidate binaries and source-built dependencies must retain accurate provenance and deployment checks.
