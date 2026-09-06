# OpenGame

macOS 上的原生 Windows 游戏管理器。SwiftUI 启动器支持 Wine、DXVK、DXMT，以及实验性的 Wine FOSS 11 + MSync 核心。

仓库同时支持轻量启动器构建和带运行核心的完整 APP 构建。完整包携带一份 Wine FOSS 11 核心、DXMT/DXVK 增量包和视频运行库，不读取用户的 Steam、游戏、存档或容器。默认 CI 快速构建启动器；正式 Release 工作流验证运行时哈希、动态依赖、干净用户目录、Developer ID 签名和 Apple 公证。

## 功能

- 创建与复制容器、导入 EXE、运行 EXE/MSI 安装器。
- 扫描默认 Steam 库、保存启动参数、工作目录和游戏原始图标。
- 新容器默认使用 Wine FOSS 11、DXMT 和 MSync；旧 WineHQ 容器仍可兼容读取。
- Steam CEF 参数包装器、重复启动检查、逐游戏日志。
- 原生应用图标；Command-Q 会先请求游戏和 Steam 正常退出，再结束各 OpenGame 容器的 Wine 服务。
- 从官方地址下载并校验 Steam、VC++ 2015–2026 和 .NET Framework 4.8 安装配方。
- 导出、检查、恢复 `.opengamebottle` 容器归档，可迁移容器内的游戏入口。
- 新安装从空游戏库开始；已有游戏库保持原样。游戏图标从用户自己的 EXE/库中提取。

## 本地构建

需要 Apple Silicon Mac、Xcode Command Line Tools，以及 LLVM-MinGW Windows x64 编译器。CI 固定使用 llvm-mingw 20260826 并校验官方 SHA-256。

```sh
export OG_MINGW_CC=/path/to/llvm-mingw/bin/x86_64-w64-mingw32-gcc
scripts/test.sh
scripts/build.sh
scripts/package.sh
```

维护者从已审计的核心生成可直接运行的 APP：

```sh
scripts/package-full.sh "$HOME/Library/Application Support/OpenGame"
```

应用位于 `build/OpenGame.app`，压缩包和校验和位于 `dist/`。普通 `package.sh` 生成启动器；`package-full.sh` 从已审计的运行时目录生成完整 APP 和对应源码包。输出为 Apple Silicon arm64，最低部署目标 macOS 14；当前实机验证覆盖 macOS 26.6.2 / M3。

GitHub Actions 在推送、PR、版本标签和手动触发时构建，产物保留 14 天。工作流只有只读仓库权限，不会自动公开仓库或发布 Release。

## 已有开发环境如何使用

将 `OpenGame.app` 放到个人 `Applications` 目录。运行目录是当前用户的 `~/Library/Application Support/OpenGame`。首次启动会建立空游戏库并安装应用自带的两个小型 Windows 辅助程序；已有配置不会被初始化覆盖。CLI 位于应用包的 `Contents/MacOS/OpenGameCLI`。

运行引擎目录约定见 [RUNTIME.md](docs/RUNTIME.md)，完整构建命令见 [BUILDING.md](runtime/BUILDING.md)。

## 发布给朋友

[分发说明](docs/DISTRIBUTION.md) 区分 Actions 编译产物与 Release 下载包。私有仓库的源码及 Release 仅对有访问权限的人开放。

正式工作流已经实现 Developer ID 签名、`notarytool` 提交和 stapling。实际签名需要仓库所有者配置 Apple Developer 证书及公证 API 密钥；没有这些凭据生成的本地包仍是临时签名预览版。

## 测试与限制

仓库测试覆盖空白首次启动、旧目录保留以及 Wine 家族路由。32/64 位窗口 Present、HTTPS 的诊断源码在 docs。此前同一微基准的五轮中位数见 [micro-summary.json](docs/micro-summary.json)：新核心四项耗时与 CrossOver DXMT + MSync 相差约 5% 以内，不能推导全部游戏或真实 FPS 等效。

Wine/VKD3D 的 x64 `D3D12CreateDevice` 探针已返回 `S_OK`，但尚未通过真实 DX12 游戏验收，不能标为与 CrossOver 的 D3DMetal 等效。Apple D3DMetal、CrossOver 专有配方和兼容数据库不进入本仓库。Wine 已用 GStreamer 1.28.1 重新编译，完整包同时包含 64 位 Unix 桥接、64/32 位 Windows 模块和白名单播放插件；自动验收会运行 OpenH264→VideoToolbox 流水线，真实游戏过场仍需逐款验证。Steam 错误报告程序有已知崩溃；其它游戏、联机与长期稳定性需要逐项验证。详见 [能力矩阵](docs/CAPABILITIES.md)。

退出时若程序拒绝 Windows 会话结束，OpenGame 会保持运行并给出“重试／取消／强制退出”。只有明确选择强制退出才会跳过保存保护。Steam 正常退出后偶发残留的 CEF／错误报告辅助进程会自动清理，不再把它误报为游戏拒绝退出。退出逻辑严格限定在 OpenGame 的 `Prefixes` 目录，不操作 CrossOver 或其它 Wine 环境。

## 许可证

原创启动器与脚本为 MIT。Steam CEF 包装器来自 MIT 项目，保留原许可证及来源提交，见 `source/steam-wrapper/`。Wine、DXVK、DXMT 和其他依赖遵循各自许可证，详见 [THIRD_PARTY.md](docs/THIRD_PARTY.md)。仓库不包含 Steam 客户端、游戏内容、第三方游戏图标、D3DMetal 或 CrossOver 专有二进制。Release 的完整 APP 可包含允许再分发的 FOSS 二进制，并同时提供完整对应源码包。
