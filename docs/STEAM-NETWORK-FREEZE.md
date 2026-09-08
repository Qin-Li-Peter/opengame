# Steam networking freeze on Darwin

OpenGame 0.5.5 fixes the Wine conversion of IPv4 TOS ancillary data. The change is in the public Wine source, not in Steam or the game.

## Evidence

On this Apple M3 Mac, How to Fish 1.0.12 froze at its main menu while connecting to Steam. The Unity main thread waited inside `SteamAPI_ManualDispatch_GetNextCallback`. The Steam networking thread owned the networking lock. A targeted Winsock trace exposed `Unhandled IPPROTO_IP message header type 27`, followed by Steam's `No control data returned even though we asked for TOS?` assertion. Replacing the crash reporter with an empty helper did not resolve the underlying failure.

Darwin returns the received IPv4 TOS byte with ancillary type `IP_RECVTOS` (27). Wine accepted `IP_TOS` but discarded that Darwin type. `runtime/patches/darwin-ip-recvtos.patch` handles both and converts the byte into the existing Windows `IP_TOS` integer control message. The extra case is guarded for Darwin and distinct constant values.

## Rebuild and test

Apply `scripts/apply-wine-patches.sh /path/to/wine-source` before configuring any Wine core. Existing matching build trees can rebuild `dlls/ntdll/ntdll.so`; stage the rebuilt module into the matching runtime, remove absolute build-directory `LC_RPATH` entries with `install_name_tool -delete_rpath`, and re-sign the module and app. Do not overwrite a running module or mix unrelated Wine builds.

Compile `tests/diagnostics/udp-tos.c` with the Windows x64 compiler and `-lws2_32`, then execute it with the staged Wine core. It sends a UDP loopback packet with TOS `0xB8`, requests receive TOS, and checks that `WSARecvMsg` returns the corresponding control message. The unpatched installed DXMT core failed with missing ancillary data; both patched base and DXMT cores passed with TOS `0xB8`.

The user then verified the game through OpenGame's normal double-click launch: the menu and background resumed working. MSync, normal multithreaded rendering, the input adapter, and the user's existing mod configuration were restored. Disabling MSync, forcing single-threaded rendering, disabling mods, and removing the input adapter had each failed to fix the freeze before the network patch. This verifies the reported menu failure, not multiplayer or comparative performance.
