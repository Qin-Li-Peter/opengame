# OpenGame

[中文](README.md) · **English**

**Install, manage, and run Windows games on an Apple Silicon Mac.**

OpenGame provides graphical Windows game environments. Install Windows Steam, download games you own, and launch them from Steam or the OpenGame library. You can also run EXE / MSI installers or add existing Windows games.

The full application includes the required runtime libraries, so you do not need CrossOver or a local build. Bring your own games, accounts, and saves; compatibility must be verified for each game.

## Download and requirements

### [Download OpenGame 0.5.8 full application (Apple Silicon · ZIP · about 1.4 GB)](https://github.com/Qin-Li-Peter/opengame/releases/download/v0.5.8/OpenGame-0.5.8-macos-arm64.zip)

[Release notes and checksums](https://github.com/Qin-Li-Peter/opengame/releases/tag/v0.5.8) · [Quick start](#quick-start-with-steam)

The full application is the **0.5.8 prerelease**, including automatic Steam discovery, multiple libraries, and refresh. Compatibility still requires verification for each game.

| Item | Requirement |
| --- | --- |
| Mac | Apple Silicon (M-series); Intel Macs are unsupported |
| System | macOS 26.0 or later; Apple Silicon |
| Rosetta | Install when prompted by macOS; see [Apple's instructions](https://support.apple.com/en-us/102527) |
| Storage | About 1.4 GB for the ZIP and 4 GB for the extracted app, plus space for environments and games |
| Network and account | Steam installation, game downloads, and online play require internet access and your own Steam account |
| Game compatibility | Primarily intended for trying DirectX 10/11 games. DirectX 12 and games requiring kernel-level anti-cheat are outside the current support scope. Multiplayer, voice chat, and cutscenes require testing per game |

Test one game before moving your library.

## Quick start with Steam

### 1. Install OpenGame

Download **`OpenGame-0.5.8-macos-arm64.zip`** above, extract it, move **OpenGame.app** to Applications, and open it. The Release's Source code and corresponding-source archives contain source code, not an installable application.

This package is not yet notarized by Apple. If macOS cannot verify the developer, confirm the download source and follow [Apple's instructions](https://support.apple.com/en-us/102445): after attempting to open the app, go to System Settings → Privacy & Security and choose Open Anyway. If macOS reports damage or malware, stop, download again, and contact the maintainer.

### 2. Create or select an environment

Click **新建容器** (New container), enter a name such as `Steam`, keep the defaults, and click **创建** (Create). You can select an existing container instead.

A container is an independent Windows environment holding programs, settings, and some saves. Steam Cloud or explicitly mapped files may share data across containers. Start with one container; the default graphics setting is **DXMT**. The labels below match the current Chinese interface.

### 3. Install and sign in to Steam

1. Select the container and click **安装应用 → Steam → 下载并安装** (Install apps → Steam → Download and install). Wait for automatic installation to finish and keep Steam’s default installation location.
2. Click **Steam** in the toolbar, sign in to your account, and complete Steam Guard verification.
3. Allow the initial setup and Steam updates to finish; this may take a few minutes.

### 4. Download a game

Install a game you own in this **Windows Steam** library, using the default library or another Steam library accessible through this container’s Windows drive mappings. Games installed through native macOS Steam need their Windows versions installed again inside this environment.

OpenGame automatically reads this container’s default Steam library and additional libraries in `libraryfolders.vdf`. External drives must be mounted and accessible through the container’s Windows drive mappings. Unavailable libraries are shown with their status.

### 5. Launch the game

- **From Steam:** Once the download finishes, click Play in your Steam library.
- **From OpenGame:** Return to OpenGame; games automatically appear under the corresponding container. If a game has not appeared, click **刷新游戏库** (Refresh library, Command-R). When its status is **已安装** (Installed), click the card’s **启动** (Launch) button; double-click also launches. Downloading or updating entries show their status; finish the installation before launching.

OpenGame's Steam game entries use the Steam client in the corresponding container, so make sure you are signed in. A successful installation or a library entry does not establish game compatibility.

Save before quitting. **Command-Q** quits OpenGame and closes games and Steam in its containers; remaining processes are cleaned up if normal shutdown fails. Save your game before quitting the launcher.

## Other games and environment management

- **Install another Windows game:** Select a container, click **运行安装程序** (Run installer), and complete the EXE / MSI installer. Then use **添加游戏** (Add game) to select the game's main executable.
- **Add an existing game:** Use **添加游戏** (Add game) to select its EXE and container. Keep the complete game folder; adding an entry does not copy its files.
- **Install dependencies:** Use **安装应用** (Install apps) in the target container to install Visual C++, .NET, or other components required by the game.
- **Configure and back up:** Use **容器工具** (Container tools) to change graphics settings or export and restore container archives. Back up game files outside the container separately.
- **Update the app:** Save and quit, download a new full application package, and replace OpenGame.app in Applications. App updates preserve existing libraries and containers.

Use games you own or are authorized to use.

## Project and contributions

Report problems or propose improvements through [Issues](https://github.com/Qin-Li-Peter/opengame/issues), including your OpenGame / macOS versions, Mac model, game name, and reproduction steps. The toolbar's **日志** (Logs) button provides diagnostic information; remove accounts, tokens, and other personal information before sharing. For code contributions, read the development and build guide and describe how you validated the change.

The original OpenGame launcher and scripts use the MIT license; runtime components retain their own licenses. The project includes no games, Steam accounts, or proprietary CrossOver components. Full Releases also provide corresponding runtime source code.

[Development and builds](docs/DEVELOPMENT.md) · [Changelog](CHANGELOG.md) · [Third-party components](docs/THIRD_PARTY.md) · [License](LICENSE)
