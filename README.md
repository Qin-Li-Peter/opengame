# OpenGame

**在 Apple Silicon Mac 上安装、管理和运行 Windows 游戏。**

OpenGame 为 Mac 提供图形化的 Windows 游戏运行环境。你可以安装 Windows 版 Steam、下载自己拥有的游戏，也可以添加已有的 Windows 游戏，在同一个游戏库中双击启动。

完整安装包已包含所需运行库，无需安装 CrossOver，也无需自己编译。游戏、Steam 账号和存档由你自行准备。

**[下载 OpenGame 0.5.7 内测版](https://github.com/Qin-Li-Peter/opengame/releases/tag/v0.5.7)** · [安装与配置](#安装与配置) · [常见问题](#常见问题)

> OpenGame 目前处于内测阶段，兼容性因游戏而异。建议先用一款游戏测试，再迁移自己的游戏库。

## 可以做什么

- 在 Mac 上安装 Windows 版 Steam，并管理已安装的 Steam 游戏。
- 安装 EXE / MSI 程序，或添加已有游戏的 EXE 文件。
- 使用游戏本身的图标展示游戏库：单击选中，双击启动。
- 为不同游戏创建独立运行环境，调整图形设置，导出和恢复环境备份。
- 退出 OpenGame 时，一并结束其容器中的游戏、Steam 和 Wine 进程。

## 使用前准备

| 项目 | 要求 |
| --- | --- |
| Mac | Apple Silicon（M 系列芯片）；当前安装包不适用于 Intel Mac |
| 系统 | macOS 14 或更新版本；目前主要在 M3 实机验证 |
| Rosetta | Wine 运行库需要 Rosetta，按 macOS 提示安装；见 [Apple 安装说明](https://support.apple.com/zh-cn/102527) |
| 磁盘 | 完整 ZIP 约 1.4 GB，解压后应用约 4 GB；另需容器和游戏所占空间 |
| 网络与账号 | 安装 Steam、下载游戏和在线游玩需要联网；使用你自己的 Steam 账号 |

当前仓库为私有仓库。下载前，请让仓库所有者邀请你的 GitHub 账号；接受邀请并登录后才能访问。如果页面显示 404，先检查账号及访问权限。

## 安装与配置

### 1. 下载并安装 OpenGame

1. 打开 [当前版本下载页](https://github.com/Qin-Li-Peter/opengame/releases/tag/v0.5.7)。
2. 下载 **`OpenGame-0.5.7-macos-arm64.zip`**。这是包含运行库的完整应用；页面上的 Source code 和 corresponding-source 是源码，不是安装包。
3. 解压，将 **OpenGame.app** 拖到 Mac 的“应用程序”文件夹，然后从那里打开。

当前内测包尚未经过 Apple 公证。如果 macOS 提示无法验证开发者，请先确认文件来自本仓库，再按 [Apple 官方说明](https://support.apple.com/zh-cn/102445)：尝试打开后，在“系统设置 → 隐私与安全性”中选择“仍要打开”。如果提示文件损坏或含恶意软件，请先停止打开、重新下载并向维护者反馈。

### 2. 创建游戏环境

点击 **新建容器**，名称可以填写 `Steam`，保留默认设置后点击 **创建**。

“容器”就是一个独立的 Windows 游戏环境，存放该环境的程序、设置和部分存档。第一次使用只需创建一个；以后遇到需要不同设置的游戏，可以再创建新容器。

默认图形设置为 **DXMT**，先使用默认值即可。

### 3. 安装并登录 Steam

1. 选中刚创建的容器，点击 **安装组件**。
2. 选择 **Steam**，点击 **下载并安装**，完成弹出的安装向导。
3. 点击工具栏的 **Steam**，在窗口中登录自己的账号，完成 Steam Guard 验证。
4. 在这个 Windows 版 Steam 中下载自己拥有的游戏。

第一次初始化或 Steam 更新可能需要几分钟。Mac 原生 Steam 中安装的 macOS 游戏不会自动变成这个容器中的 Windows 游戏，需要在此处安装 Windows 版本。

### 4. 将游戏加入 OpenGame 并启动

游戏在 Steam 中安装完成后，回到 OpenGame，选中对应容器，打开 **容器工具 → 扫描已安装的 Steam 游戏**。

游戏出现后，**单击卡片选中，双击卡片启动**。Steam 游戏会通过对应容器的 Steam 客户端启动；首次使用请确认 Steam 已完成登录。

退出前先保存游戏。按 **Command-Q** 退出 OpenGame 时，会一并结束其容器中的游戏和 Steam；正常退出失败时会清理残留进程。

## 安装其他 Windows 游戏

- **有安装程序：** 选中目标容器，点击 **运行安装程序**，选择 EXE 或 MSI 并完成安装；随后通过 **添加游戏** 选择安装后的游戏 EXE。
- **已有完整游戏文件夹：** 点击 **添加游戏**，选择游戏 EXE 和要使用的容器。保留整个游戏文件夹；添加入口不会复制游戏文件。
- **提示缺少运行库：** 在目标容器中打开 **安装组件**，按游戏要求安装 Visual C++ 或 .NET 等组件。

请使用自己拥有或获授权的游戏文件。

## 更新 OpenGame

1. 保存游戏并退出 OpenGame，等待游戏和 Steam 关闭。
2. 从下载页获取新版本，解压后替换“应用程序”中的 OpenGame.app。
3. 重新打开应用。游戏库和容器存放在 `~/Library/Application Support/OpenGame`，更换应用本身不会删除这些数据。

重要容器可以先通过 **容器工具 → 导出容器归档** 备份。放在容器外部的游戏文件需要另行备份。

## 常见问题

**游戏库为什么是空的？**

新安装不会附带游戏。先在容器内安装 Steam 和游戏，再扫描已安装的 Steam 游戏；其他游戏使用“添加游戏”。

**单击游戏为什么没有运行？**

单击用于选中，双击才会启动。

**Steam 黑屏、一直连接，或游戏没有响应怎么办？**

先确认 Steam 已登录并完成更新。若持续无响应，记录出现问题的操作，从 OpenGame 工具栏的 **日志** 打开相关日志，并向维护者反馈。不要连续双击尝试启动多个副本。

**帧率低怎么办？**

先降低游戏分辨率和画质，关闭其他高负载程序。默认使用 DXMT；如需试用其他图形后端，可在 **容器工具 → 容器设置与图形后端** 中更改。不同游戏的效果不同。

**语音没有声音怎么办？**

检查 macOS“系统设置 → 隐私与安全性 → 麦克风”中的 OpenGame 权限，以及游戏内的输入设备设置。当前语音和联机功能仍需逐款验证。

## 兼容性与已知问题

- 当前以 DirectX 10/11 游戏为主要尝试对象。不能保证所有 Windows 游戏运行，也不能保证达到 CrossOver 的性能。
- DirectX 12 游戏及依赖内核级反作弊的游戏不在当前支持范围内。
- 《渔力全开》已有 Steam 登录、菜单和输入的使用验证；**创建房间曾出现卡住，联机和语音仍未完成完整复测**。
- 当前安装包尚未 Apple 公证，也尚未完成第二台全新 Mac 的完整游玩验收。

遇到问题，请通过 [Issues](https://github.com/Qin-Li-Peter/opengame/issues) 或联系维护者，提供 Mac 型号、macOS / OpenGame 版本、游戏名称、复现步骤、截图和相关日志。分享前删去账号、令牌等个人信息。

## 项目信息

OpenGame 启动器与原创脚本采用 MIT 许可证，运行库遵循各自许可证。项目不附带 Steam 账号、游戏内容或 CrossOver 专有组件。每个完整 Release 同时提供运行库对应源码。

[更新记录](https://github.com/Qin-Li-Peter/opengame/blob/main/CHANGELOG.md) · [开发与构建](https://github.com/Qin-Li-Peter/opengame/blob/main/docs/DEVELOPMENT.md) · [第三方组件](https://github.com/Qin-Li-Peter/opengame/blob/main/docs/THIRD_PARTY.md) · [许可证](LICENSE)
