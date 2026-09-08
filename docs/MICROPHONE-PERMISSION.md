# Microphone initialization on macOS

OpenGame 0.5.6 declares `NSMicrophoneUsageDescription` and the hardened-runtime `com.apple.security.device.audio-input` entitlement. Access remains subject to the user's macOS permission choice; the launcher does not modify TCC permissions.

In How to Fish, creating a room starts the FishySteamworks server and connects the local client before opening voice capture. The previous bundle lacked a microphone usage description. The main thread then waited in `CoreAudio_request_capture_authorization`, while the authorization callback entered `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__`. macOS attributed the request to `local.opengame.launcher`. Wine's waiting thread made this appear to be a frozen game instead of a normal permission request.

Validation must include creating a room and responding to the macOS permission prompt; reaching the main menu does not exercise capture initialization. Record permission choice and whether room controls remain responsive. Do not reset existing user permissions for testing.

After installing 0.5.6, TCC logged `AUTHREQ_PROMPTING` for `local.opengame.launcher` and the microphone service. This confirms the request now reaches the normal permission flow. End-to-end room validation is still awaiting the user's permission choice and interaction check.
