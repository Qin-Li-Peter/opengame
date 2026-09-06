# OpenGame

macOS 上的原生 Windows 游戏管理器。SwiftUI 启动器支持 Wine、DXVK、DXMT，以及实验性的 Wine FOSS 11 + MSync 核心。

**当前仓库为开发预览。CI 产物只包含启动器，不包含 Wine 引擎，不能在全新 Mac 上直接运行 Windows 游戏。** 本机配置的默认 Wine FOSS 11 核心可启动《渔力全开》和《巴别塔圣歌》，但引擎的可移植安装和完整分发包尚未完成。不能把启动器编译通过等同于完整产品发布通过。

## 功能

- 创建与复制容器、导入 EXE、运行 EXE/MSI 安装器。
- 扫描默认 Steam 库、保存启动参数、工作目录和游戏原始图标。
- 新容器默认使用 Wine FOSS 11、DXMT 和 MSync；旧 WineHQ 容器仍可兼容读取。
- Steam CEF 参数包装器、重复启动检查、逐游戏日志。
- 原生应用图标；Command-Q 会先请求游戏和 Steam 正常退出，再结束各 OpenGame 容器的 Wine 服务。
- 新安装从空游戏库开始；已有游戏库保持原样。游戏图标从用户自己的 EXE/库中提取。

## 本地构建

需要 Apple Silicon Mac、Xcode Command Line Tools，以及 LLVM-MinGW Windows x64 编译器。CI 固定使用 llvm-mingw 20260826 并校验官方 SHA-256。

```sh
export OG_MINGW_CC=/path/to/llvm-mingw/bin/x86_64-w64-mingw32-gcc
scripts/test.sh
scripts/build.sh
scripts/package.sh
```

应用位于 `build/OpenGame.app`，压缩包和校验和位于 `dist/`。构建不读取或打包本机 Steam、游戏、存档、账号、容器或运行日志。输出为 Apple Silicon arm64 启动器，最低部署目标 macOS 14；Windows 运行能力取决于另行配置的引擎与系统版本，当前实机验证仅覆盖 macOS 26.6.2 / M3。

GitHub Actions 在推送、PR、版本标签和手动触发时构建，产物保留 14 天。工作流只有只读仓库权限，不会自动公开仓库或发布 Release。

## 已有开发环境如何使用

将 `OpenGame.app` 放到个人 `Applications` 目录。运行目录是当前用户的 `~/Library/Application Support/OpenGame`。首次启动会建立空游戏库并安装应用自带的两个小型 Windows 辅助程序；已有配置不会被初始化覆盖。CLI 位于应用包的 `Contents/MacOS/OpenGameCLI`。

运行引擎目录约定和本机实现说明见 [RUNTIME.md](docs/RUNTIME.md)。没有引擎时不要将该包提供为“一键安装后可玩”的正式版。

## 发布给朋友

[分发说明](docs/DISTRIBUTION.md) 区分 Actions 编译产物与 Release 下载包，列出完整包目前缺少的工作。私有仓库的源码及 Release 仅对有访问权限的人开放。

目前二进制只有本地临时签名，未进行 Developer ID 签名和 Apple 公证。朋友的 macOS 可能拦截下载的应用；正式分发流程应补齐签名／公证，不提供关闭系统安全功能的安装脚本。

## 测试与限制

仓库测试覆盖空白首次启动、旧目录保留以及 Wine 家族路由。32/64 位窗口 Present、HTTPS 的诊断源码在 docs。此前同一微基准的五轮中位数见 [micro-summary.json](docs/micro-summary.json)：新核心四项耗时与 CrossOver DXMT + MSync 相差约 5% 以内，不能推导全部游戏或真实 FPS 等效。

当前缺少 DX12/D3DMetal、DLSS、自动安装配方和完整容器归档恢复。FOSS 核心未编入 GStreamer；Steam 错误报告程序有已知崩溃；其它游戏、联机与长期稳定性需要逐项验证。

退出时若程序拒绝 Windows 会话结束，OpenGame 会保持运行并给出“重试／取消／强制退出”。只有明确选择强制退出才会跳过保存保护。Steam 正常退出后偶发残留的 CEF／错误报告辅助进程会自动清理，不再把它误报为游戏拒绝退出。退出逻辑严格限定在 OpenGame 的 `Prefixes` 目录，不操作 CrossOver 或其它 Wine 环境。

## 许可证

原创启动器与脚本为 MIT。Steam CEF 包装器来自 MIT 项目，保留原许可证及来源提交，见 `source/steam-wrapper/`。Wine、DXVK、DXMT 和其他依赖遵循各自许可证，详见 [THIRD_PARTY.md](docs/THIRD_PARTY.md)。仓库不包含 Steam 客户端、游戏内容、第三方游戏图标或 CrossOver 专有二进制。
