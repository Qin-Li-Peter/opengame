# OpenGame 快速开始

OpenGame 让你在 Apple Silicon Mac 上安装和运行 Windows 游戏。完整包包含运行库，无需安装 CrossOver；请自行准备 Steam 账号和游戏。

**[当前下载页](https://github.com/Qin-Li-Peter/opengame/releases/tag/v0.5.7)** · **[完整安装与使用说明](https://github.com/Qin-Li-Peter/opengame#安装与配置)**

1. 接受仓库所有者的 GitHub 邀请并登录，再从下载页获取 `OpenGame-0.5.7-macos-arm64.zip`。Source code 和 corresponding-source 是源码，不是安装包。
2. 使用 Apple Silicon Mac、macOS 14 或更新版本。运行库需要 [Rosetta](https://support.apple.com/zh-cn/102527)，按 macOS 提示安装。
3. 解压，将 OpenGame.app 拖到“应用程序”后打开。当前内测包尚未 Apple 公证；遇到开发者验证提示时，确认来源后参考 [Apple 打开说明](https://support.apple.com/zh-cn/102445)。
4. 点击“新建容器”，名称填 Steam，保留默认 DXMT 设置并创建。
5. 选择容器，点击“安装组件 → Steam → 下载并安装”；完成向导后通过工具栏的“Steam”登录自己的账号。
6. 在这个 Windows Steam 中安装自己的游戏。回到 OpenGame，通过“容器工具 → 扫描已安装的 Steam 游戏”加入游戏库。
7. 单击选中，双击启动。先保存游戏再用 Command-Q 退出；退出 OpenGame 会一并结束其容器中的游戏、Steam 和 Wine。

非 Steam 游戏使用“运行安装程序”安装，再通过“添加游戏”选择实际 EXE。已有游戏请保留完整文件夹。

当前为内测版。《渔力全开》创建房间曾卡住，联机、语音仍需复测；DX12 和内核级反作弊游戏不在当前支持范围。遇到问题请记录机型、系统版本、游戏名和操作步骤，从工具栏“日志”获取相关记录后联系维护者。
