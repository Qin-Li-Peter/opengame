# OpenGame 快速开始

OpenGame 让你在 Apple Silicon Mac 上安装和运行 Windows 游戏。完整包包含运行库，无需安装 CrossOver；请自行准备 Steam 账号和游戏。

**[当前下载页](https://github.com/Qin-Li-Peter/opengame/releases/tag/v0.5.8)** · **[完整安装与使用说明](https://github.com/Qin-Li-Peter/opengame#快速开始以-steam-为例)**

1. 从公开下载页获取 `OpenGame-0.5.8-macos-arm64.zip`。Source code 和 corresponding-source 是源码，不是安装包。
2. 使用 Apple Silicon Mac、macOS 26.0 或更新版本。运行库需要 [Rosetta](https://support.apple.com/zh-cn/102527)，按 macOS 提示安装。
3. 解压，将 OpenGame.app 拖到“应用程序”后打开。当前内测包尚未 Apple 公证；遇到开发者验证提示时，确认来源后参考 [Apple 打开说明](https://support.apple.com/zh-cn/102445)。
4. 点击“新建容器”，名称填 Steam，保留默认 DXMT 设置并创建。
5. 选择容器，点击“安装应用 → Steam → 下载并安装”；自动安装完成后通过工具栏的“Steam”登录自己的账号。
6. 在这个 Windows Steam 中安装自己的游戏。回到 OpenGame，游戏将自动出现；未出现时点击“刷新游戏库”。可发现本容器盘符映射可访问的多个 Steam 库。
7. 状态为“已安装”时点击“启动”；也可双击卡片。先保存游戏再用 Command-Q 退出；退出 OpenGame 会一并结束其容器中的游戏、Steam 和 Wine。

非 Steam 游戏使用“运行安装程序”安装，再通过“添加游戏”选择实际 EXE。已有游戏请保留完整文件夹。

当前为内测版。联机、语音与不同游戏的兼容性需分别验证；DX12 和内核级反作弊游戏不在当前支持范围。遇到问题请记录机型、系统版本、游戏名和操作步骤，从工具栏“日志”获取相关记录后联系维护者。
