# Changelog

## 0.5.2

- Steam 游戏改由已登录的 Steam 客户端通过 `-applaunch` 启动，不再把直接运行 EXE 后由游戏自行重启作为正常路径；启动前同时确认客户端、CEF 和 Steam 网络登录状态，冷启动会等待 IPC 稳定后再转发游戏命令。
- Steam 主进程也会继承覆盖层隔离设置，避免 `gameoverlayui64.exe` 与 DXMT 游戏窗口争用图形交换链。
- Command-Q 先给游戏和 Steam 五秒正常结束时间，随后自动关闭 OpenGame 管理的 Wine 会话，不再要求用户二次选择“强制退出”。

## 0.5.1

- 修正完整包把基础 Wine 与 DXMT Windows DLL 混用的问题。DXMT 现在携带并使用完整匹配核心，Steam CEF 与游戏也始终共用同一 Wine 进程和 wineserver，消除冷启动时随机出现的 D3D11 初始化失败。
- 渲染器标记不再是唯一判断依据；每次启动会核对 32/64 位 D3D DLL 的实际内容，Wine 或 Steam 更新将文件还原后会自动修复。
- Steam 游戏默认关闭注入式覆盖层，避免 DXMT 0.80 因跨进程交换链请求导致 Unity 首次启动失败。
- Steam 启动加入 `-noverifyfiles`，不再因 CEF 参数包装器在每次冷启动时反复下载同一客户端更新；仅清理由 Wine 非原子更新留下且与现文件逐字节相同的 `.old` 副本。
- 新增原创的静默错误报告兼容程序。OpenGame 会先备份 Valve 的 64 位错误报告器，再接管这个在 Wine 下会自行崩溃的可选辅助进程；Steam 更新恢复原文件后会自动重新应用。
- 冷启动 Steam 时等待客户端与 CEF 都稳定出现后再启动目标游戏，减少用户重复点击和启动竞争。
- Steam 启动器提前返回非零代码时继续等待真实游戏进程，避免把较慢的冷启动误报为失败；游戏已经运行时再次点击会立即识别并尝试显示现有窗口。

## 0.5.0

- 新增可携带 Wine FOSS 11、DXMT、DXVK 和 GStreamer 1.28.1 的完整 APP 打包流程；Wine 已构建 x86_64/i386 `winegstreamer` 桥接，三个图形后端共用一份 Wine 核心，只发布六个不同的 Direct3D DLL，消除约 3.3 GB 重复文件。
- 打包时自动重写构建机绝对动态库路径，并拒绝逃逸符号链接、Steam 登录数据、容器注册表和非系统绝对依赖。
- 新增 Steam、VC++ 2015–2026 和 .NET Framework 4.8 自有安装配方。下载限定官方 HTTPS 域名并校验 SHA-256。
- 完整包加入 SIL OFL 授权的 Liberation 字体，并为 Arial、Times New Roman、Courier New 配置替代字体。
- 新增 `.opengamebottle` 容器归档、路径安全检查、恢复及跨用户路径迁移。
- 新增完整对应源码下载与打包、Developer ID 签名、公证和干净 HOME 验收脚本，以及手动正式 Release 工作流。
- GStreamer 分发改用显式组件白名单，排除 GPL/restricted/DVD 组件；源码包会校验并收录其 46 个 wrap 依赖归档。
- 修正 universal 运行库路径重写后的签名顺序，逐个签署 Mach-O 后再签应用；容器归档同时拒绝越界符号链接。
- 完整包优先使用 APP 内运行核心；原有本地引擎仍作为开发环境回退。

## 0.4.3

- 图形界面新建容器固定使用 Wine FOSS 11、DXMT 和 MSync，不再提供旧核心选项，也不再使用“性能版”产品命名。
- 输入适配器根据容器配置选择运行核心，移除对 WineHQ11 的硬编码。
- 版本号在界面中从应用包读取，避免发布时残留旧版本文字。
- 从冷启动点击 Steam 游戏时先准备 Steam，再启动游戏；退出时将这类游戏纳入 Steam 残留清理。

## 0.4.2

- 添加 OpenGame 的 macOS 应用图标，并在侧边栏显示品牌图标。
- 接入 macOS 应用退出生命周期。Command-Q 会停止新启动、等待正在进行的容器操作、终止 Steam 兼容监控，并逐个关闭 OpenGame 管理的 Wine 容器。
- 通过 Wine 会话结束消息给游戏保存和拒绝退出的机会；失败时提供重试、取消和明确的强制退出选项。
- 自动清理 Steam 正常退出后残留的 CEF 和错误报告辅助进程，同时保留真正拒绝退出的游戏进程。
- 新增独立容器、拒绝退出、强制退出、跨容器隔离和真实 Wine 脱离子进程测试。
