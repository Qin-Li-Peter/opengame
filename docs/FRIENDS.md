# OpenGame 0.5.7 朋友内测指南

## 下载与安装

下载页面：https://github.com/Qin-Li-Peter/opengame/releases/tag/v0.5.7

仓库目前是私有的。作者需要先在仓库 Settings → Collaborators 中邀请你的 GitHub 账号，你接受邀请并登录后才能访问。404 通常表示未登录或没有权限。

下载 `OpenGame-0.5.7-macos-arm64.zip`，不是页面自动提供的 Source code。ZIP 内含应用、Wine 运行库和说明；不含账号、游戏、存档，无需安装 CrossOver。`corresponding-source.tar.xz` 是运行库对应源码，普通玩家不用下载。

需要 Apple Silicon Mac（M1/M2/M3/M4 等）和 macOS 14 或更新版本；目前主要在 M3 上验证。解压后把 OpenGame.app 拖到“应用程序”，从那里打开。不要只复制桌面快捷方式。

此内测包只有本地签名，尚未经过 Apple 公证。如出现无法验证开发者提示，在确认下载来自上述仓库后，按 Apple 官方说明：先尝试打开，再到“系统设置 → 隐私与安全性 → 仍要打开”。不要关闭系统整体安全保护。若提示恶意软件或文件已损坏，先核对下载与 SHA256SUMS.txt 并联系作者。
Apple 说明：https://support.apple.com/zh-cn/102445

## 首次配置 Steam

1. 打开 OpenGame，点击“新建容器”，名称可填 Steam。使用默认 Wine FOSS 11、DXMT、Windows 10 配置。
2. 选中这个容器，点击“安装组件”，选择 Steam，完成官方安装向导。首次初始化可能需要几分钟。
3. 点击工具栏的“Steam”，使用你自己的 Steam 账号登录，自行完成 Steam Guard 验证。
4. 在这个 Windows Steam 客户端中安装自己拥有的游戏。原生 macOS Steam 的安装不会自动成为本容器中的 Windows 安装。
5. 回到 OpenGame，选中容器，在“容器工具”中选择“扫描已安装的 Steam 游戏”。

## 玩游戏

单击游戏卡片只选中，双击启动。Steam 游戏由 Steam 客户端启动；保持 Steam 在线并完成登录。不要直接启动游戏文件来绕过 Steam。

第一次先用默认 DXMT 设置和较低分辨率测试。支持情况因游戏而异，DX12 和内核级反作弊游戏不能保证可用。不要承诺与 CrossOver 同等兼容性或性能。

游戏需要语音时，macOS 可能请求麦克风权限；可在隐私与安全性中管理。退出前先保存，Command-Q 退出 OpenGame 会连带结束本应用启动的 Steam、Wine 和游戏。

非 Steam 游戏：在目标容器使用“运行安装程序”安装 EXE/MSI，然后“添加游戏”选择实际游戏 EXE。保留完整游戏目录，不要只移动 EXE。缺少 VC++ 时，可通过“安装组件”安装对应运行库。

## 已知验证范围与问题反馈

此版本通过启动/退出等自动化回归测试，已有《渔力全开》登录、菜单与输入的使用验证。创建房间、联机、语音及其他游戏仍需朋友实际测试；此前创建游戏卡住的问题尚无完整复测结论，因此以内测版发布。

卡住时记录游戏名、Mac 型号、macOS 版本、渲染设置、具体操作和错误截图，从 OpenGame 日志入口获取相应日志后反馈给作者。不要公开 Steam 密码、验证码、登录令牌或整份个人容器。
