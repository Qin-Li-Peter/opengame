<div align="center">

<img src="resources/AppIcon.png" width="112" alt="OpenGame">

# OpenGame

### Windows 游戏，你的 Mac，一个游戏库。

**在 Apple Silicon Mac 上安装、管理和运行 Windows 游戏。**

[下载 0.5.8](https://github.com/Qin-Li-Peter/opengame/releases/download/v0.5.8/OpenGame-0.5.8-macos-arm64.zip) · [快速开始](#快速开始以-steam-为例) · [文档](docs/DEVELOPMENT.md) · [版本](https://github.com/Qin-Li-Peter/opengame/releases) · [English](README.md) · **简体中文**

</div>

OpenGame 提供图形化的 Windows 游戏环境：安装 Windows 版 Steam、下载自己拥有的游戏，再从 Steam 或 OpenGame 游戏库启动。你也可以安装其他 EXE / MSI 程序，或添加已有的 Windows 游戏。

完整安装包包含所需运行库，无需安装 CrossOver 或自行编译。游戏、账号和存档由你自行准备；游戏兼容性需要逐款验证。

## 你可以做什么

- **从一个游戏库启动：** 安装 Windows Steam，下载自己拥有的游戏，从对应容器运行。
- **管理游戏环境：** 自动发现盘符映射可访问的多个 Steam 库，刷新游戏状态，调整或备份容器。
- **添加其他游戏：** 运行 EXE / MSI 安装程序，或添加已有 Windows 主程序；入口不会复制游戏文件夹。

## 下载与系统要求

### [下载 OpenGame 0.5.8 完整安装包（Apple Silicon · ZIP · 约 1 GB）](https://github.com/Qin-Li-Peter/opengame/releases/download/v0.5.8/OpenGame-0.5.8-macos-arm64.zip)

[版本说明与校验文件](https://github.com/Qin-Li-Peter/opengame/releases/tag/v0.5.8) · [快速开始](#快速开始以-steam-为例)

当前完整包是 **0.5.8 内测版**，包含 Steam 游戏自动发现、多库扫描和刷新。游戏兼容性仍需逐款验证。

| 项目 | 要求 |
| --- | --- |
| Mac | Apple Silicon（M 系列芯片）；不支持 Intel Mac |
| 系统 | macOS 26.0 或更新版本；Apple Silicon |
| Rosetta | 按 macOS 提示安装；见 [Apple 安装说明](https://support.apple.com/zh-cn/102527) |
| 磁盘 | ZIP 约 1 GB，解压后应用约 2.6 GB；另需游戏环境和游戏所占空间 |
| 网络与账号 | Steam 安装、游戏下载和在线游玩需要联网及自己的 Steam 账号 |
| 游戏兼容性 | 以 DirectX 10/11 游戏为主要尝试对象；DirectX 12 和依赖内核级反作弊的游戏不在当前支持范围内。联机、语音与过场视频仍需逐款验证 |

建议先测试一款游戏，再迁移游戏库。

## 快速开始：以 Steam 为例

### 1. 安装 OpenGame

下载上面的 **`OpenGame-0.5.8-macos-arm64.zip`**，解压后将 **OpenGame.app** 拖到“应用程序”文件夹并打开。Release 中的 Source code 和 corresponding-source 是源码，不是可安装应用。

当前包尚未经过 Apple 公证。如果 macOS 提示无法验证开发者，确认下载来源后，按 [Apple 官方说明](https://support.apple.com/zh-cn/102445)，在尝试打开后进入“系统设置 → 隐私与安全性”选择“仍要打开”。若提示文件损坏或含恶意软件，停止打开，重新下载并向维护者反馈。

### 2. 创建或选择游戏环境

点击 **新建容器**，填写名称（例如 `Steam`），保留默认设置并点击 **创建**；已有容器可直接选中。

“容器”是独立的 Windows 游戏环境，保存程序、设置和部分存档；Steam 云同步或显式映射的文件可能跨容器共享。第一次使用创建一个即可，默认图形设置为 **DXMT**。

### 3. 安装并登录 Steam

1. 选中目标容器，点击 **安装应用 → Steam → 下载并安装**，等待自动安装完成，保留 Steam 默认安装位置。
2. 点击工具栏的 **Steam**，登录自己的账号并完成 Steam Guard 验证。
3. 等待首次初始化和 Steam 更新完成，可能需要几分钟。

### 4. 下载游戏

在这个 **Windows 版 Steam** 的游戏库中安装自己拥有的游戏，可以保留默认游戏库位置，也可使用此容器 Windows 盘符映射到的其他 Steam 库。Mac 原生 Steam 中的 macOS 游戏需要在此环境中重新安装 Windows 版本。

OpenGame 自动读取这个容器的 Steam 默认库和 `libraryfolders.vdf` 中的其他库。移动硬盘等外部库需先挂载，并能通过本容器的 Windows 盘符访问；库暂不可用时显示相应状态。

### 5. 启动游戏

- **从 Steam 启动：** 下载完成后，在 Steam 游戏库中点击“开始游戏”。
- **从 OpenGame 启动：** 回到 OpenGame，游戏会自动出现在对应容器的列表中；若尚未出现，点击 **刷新游戏库**（Command-R）。确认状态为“已安装”后，点击卡片的 **启动**；双击卡片也可启动。下载或更新中的入口会显示状态，完成后再启动。

OpenGame 中的 Steam 游戏入口会调用对应容器的 Steam 客户端，请先确保 Steam 已登录。安装成功或出现入口不代表该游戏已经通过兼容性验证。

退出前保存游戏。**Command-Q** 退出 OpenGame 会同时结束其容器中的游戏和 Steam；正常退出失败时会清理残留进程，退出启动器前务必先保存。

## 其他游戏与环境管理

- **安装其他 Windows 游戏：** 选中容器，点击 **运行安装程序**，选择 EXE / MSI 完成安装，再用 **添加游戏** 选择游戏主程序。
- **添加已有游戏：** 用 **添加游戏** 选择 EXE 和容器。保留完整游戏文件夹；添加入口不会复制游戏文件。
- **补充运行库：** 在目标容器的 **安装应用** 中按游戏要求安装 Visual C++、.NET 等组件。
- **调整与备份环境：** 在 **容器工具** 中更改图形设置、导出或恢复容器归档。容器外的游戏文件需另行备份。
- **更新应用：** 保存游戏并退出后，下载新完整包，替换“应用程序”中的 OpenGame.app。应用更新会保留已有游戏库和容器。

请使用自己拥有或获授权的游戏文件。

## 项目与贡献

遇到问题或希望贡献改进，请通过 [Issues](https://github.com/Qin-Li-Peter/opengame/issues) 提供 OpenGame / macOS 版本、Mac 型号、游戏名称和复现步骤。可从工具栏的 **日志** 获取诊断信息；分享前移除账号、令牌等个人信息。代码贡献请先阅读开发与构建说明，并说明验证方式。

OpenGame 原创启动器与脚本采用 MIT 许可证，运行库遵循各自许可证。项目不附带游戏、Steam 账号或 CrossOver 专有组件；完整 Release 同时提供运行库对应源码。

[开发与构建](docs/DEVELOPMENT.md) · [更新记录](CHANGELOG.md) · [第三方组件](docs/THIRD_PARTY.md) · [许可证](LICENSE)
