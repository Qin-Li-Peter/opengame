# OpenGame 与 CrossOver 二进制对齐分析

这是 OpenGame 0.5.7 的基线分析；后续 0.5.8 开发进展见 ALIGNMENT-0.5.8.md。

日期：2026-10-13。环境：Apple Silicon / macOS 26.6.2。
样本：CrossOver 26.3 本机安装；OpenGame v0.5.7 官方仓库发布包；源码 ecb0f60。
OpenGame ZIP SHA-256：04f01ad01569b6cbf07a233e0cedbbd73c1c06da7be777a3425cac94eb08aef1。

## 结论与证据边界

没有证据表明 OpenGame 的所有底层渲染都明显慢于 CrossOver。同为 DXMT 的本次合成着色/绘制负载接近。体验差异应分解为 API 与格式覆盖、Steam 启动与 CEF、依赖安装、视频/输入以及实际游戏工作负载。无法在没有具体游戏和场景的情况下给出真实 FPS、1% low 或长期闪退率。

当前并未达到 CrossOver 全功能、全游戏、全平台 1:1。界面模仿与共享 FOSS Wine 源码不能补齐未捆绑的 D3DMetal，也不能替代逐游戏兼容配置和验收。二进制字节不同、文件更大或导入更多库，本身都不是性能优劣的证据。

## 二进制与运行链路

CrossOver 界面为 arm64/x86_64 universal；OpenGame 界面为 arm64。两者用于这批 Windows 游戏的 Wine 加载链均为 x86_64，需要 Apple Silicon 的翻译路径，不能据此归因于 OpenGame 界面架构。

OpenGame 的清单声明基于 CrossOver 26.3.0 FOSS Wine、完整匹配 DXMT 0.80 核心、DXVK 增量 DLL 和 GStreamer 1.28.1。实际发布包存在两个完整 Wine 核心、Mono 10.4.1 和 Gecko 2.47.4。CrossOver 还存在 D3DMetal.framework，并且日常 Steam 容器配置为 D3DMetal + MSync；该日常配置不等于所有过去游戏都使用相同后端。

运行期间已通过 lsof 核对实际加载模块：两套 DXMT 分别加载各自 winemetal.so、d3d11.dll、dxgi.dll；D3DMetal 组合加载 CrossOver 的 D3DMetal.framework 与 apple_gptk 下的 D3D11/DXGI。后端结论同时有配置与实际模块证据。

本次静态扫描记录 27 项 OpenGame 和 24 项 CrossOver 二进制的架构、SHA-256、尺寸及 Mach-O 动态依赖。该计数是所选模块集合，不是产品组件总数。

OpenGame 的 Steam 兼容包装器强制 --disable-gpu --single-process；启动参数含 -cef-disable-gpu 和 -noverifyfiles。源码会改写 steamwebhelper.exe，更新后在有限监控窗口内恢复包装器并 taskkill 重启 helper。CPU 绘制可能增加界面负担；单进程模式减少故障隔离；替换和重启与 Steam 自动更新之间存在维护成本。它们是明确的实现差异与待测风险，不是已证明的旧报错原因。CrossOver 本机 10 月 9 日的 webhelper 日志显示独立 renderer/utility 进程，与该包装模式不同；此日志不是本次现场 Steam 性能测量。

OpenGame 的图形/输入补丁有逐游戏条件：例如仅对 How to Fish 的特定 EXE/Steam ID 安装 version.dll 输入适配器。这样的补丁不能视为通用 Windows 指针 API 完整实现。

## 格式能力探针

三个组合：OpenGame DXMT、CrossOver DXMT、CrossOver D3DMetal。D3D11 设备创建均成功，探针请求的默认 feature level 返回 11_0；未穷举最高级别。

13 项非视频纹理创建均成功：RGBA8、BGRA8、RGBA16F、RGB32F、R11G11B10F、RGB10A2、BC1、BC3、BC5、BC6H、BC7、D24S8、D32F。只证明指定 64x64、单采样、单 mip、特定绑定用途的纹理可创建，不证明全部顶点格式、SRV/DSV/UAV 组合、跨进程共享、视频解码或真实游戏等效。

两套 DXMT 的 CheckFormatSupport 对 NV12/YUY2 返回 E_INVALIDARG。D3DMetal 在这项查询中返回全部位为 1 的宽泛 mask，因此不能直接从 mask 推断每种用途都受支持。最终探针对视频格式只做查询，未进行视频纹理创建。不能把这些查询结果推导为 GStreamer 不支持某种视频编码。

第一版探针错误地按 mask 推断深度绑定，并对视频格式使用通用纹理描述符，曾导致 D3DMetal 断言。该探针已修正；初始结果不用于产品优劣结论。

## 合成性能结果

使用相同 benchmark.exe，预热后按轮次轮换三个后端的执行顺序，三轮有效样本取中位数。GPU 时间包含 CPU 提交、完成等待与 GPU 工作，不是游戏帧时间。全部有效运行退出码 0，像素读回验证 PASS。仅代表本机本次负载。

| 指标 | OpenGame DXMT | CrossOver DXMT | CrossOver D3DMetal |
| --- | ---: | ---: | ---: |
| cpu_ms | 85.930800 | 94.460700 | 92.663200 |
| event_roundtrip_us | 5.781210 | 2.720660 | 5.871190 |
| shader1280_median_ms | 0.851550 | 0.836500 | 0.861500 |
| draw1500_median_ms | 0.649800 | 0.649050 | 0.682900 |

OpenGame 相对 CrossOver DXMT：本次着色负载约慢 1.8%，密集绘制约慢 0.12%；CPU 循环约快 9%。事件往返延迟在各轮明显波动：OpenGame 4.17–5.89 us，CrossOver DXMT 2.59–5.86 us。不能把这些结果外推为整款游戏性能，也不能单独从三个样本推断同步实现的普遍优劣。

## 本轮已落地的代码

1. DXMT 核心缺失时明确失败，取消退回基础 Wine 的行为；避免 Wine/Unix 模块与 DXMT DLL 混用。
2. 运行中禁止切换图形后端、M同步或帧率设置；只终止用于查询的等待 helper，不主动终止用户游戏。
3. 容器增加可持久化的 MSync 和 DXMT 帧率上限：不限、30、60、120。旧 catalog 默认仍为 MSync 开启、不限帧。复制和归档恢复保留这些设置；Steam 的环境也保留帧率配置，供其子游戏继承。DXMT_CONFIG 覆盖单项帧率设置，保留 dxmt.conf 其他选项；该机制依据 DXMT v0.80 config.cpp 核对。
4. 日志记录运行库、MSync、DLL override、DXMT 配置和覆盖层参数，便于复现实验。
5. CLI run --wait 取消通用 120 秒超时杀进程行为。GUI 游戏启动原来就没有该两分钟限制，不能把 CLI 风险描述成所有 GUI 游戏中断原因。
6. Swift 发布构建使用 -O 和 whole-module-optimization，优化界面/管理层，不宣称因此提高 Wine 游戏 FPS。
7. 增加静态二进制对比工具和 D3D11 格式能力探针，并扩展性能设置、运行中保护及归档复制回归测试。

这些是本地源码修改，尚未形成新版本完整运行库发布包。基准测量的是原 v0.5.7 运行库，不是新开发版本的整机游戏性能。

## 测试弹窗与路径问题

最初将 APP 放入过深的工作目录，Mono DLL 完整路径约 267 字符。Wine mscoree 的相关查找使用 MAX_PATH 缓冲区；测试中出现 Mono 找不到提示、初始化页错误和等待超时。缩短 APP 路径后，在保留 MSync 且不屏蔽 Mono/Gecko 的全新容器中探针成功，未再出现提示或页错误。WINEDATADIR 实际解析正确。之前关于“包里缺少 Mono”的判断已撤回。

这证明深路径是当前测试失败的重要条件，不能据此声称常规 /Applications 安装也必然失败。初始化能力验收需要分别覆盖常规安装路径和长路径；不能以禁用 mscoree/mshtml 替代 .NET/HTML 验收。

## 1:1 对齐开发路线

| 优先级 | 差距/工作 | 验收标准 |
| --- | --- | --- |
| P0 | 完整核心一致性、稳定的容器配置、可复现诊断 | 缺模块启动前失败；切换不污染运行中容器；日志能识别实际模块 |
| P0 | 建立双产品差分测试集 | 每次都核对实际后端、同一程序/分辨率/画质/MSync/缓存状态；输出退出码、正确像素、frame-time |
| P1 | Steam 兼容配置替代硬编码 helper 改写 | 冷启动、登录、下载、自动更新、CEF 多进程、overlay 分项验收；旧补丁可回滚 |
| P1 | 图形 API 与资源用途矩阵 | 格式、SRV/DSV/UAV、MSAA、资源共享、交换链、着色器编译及 DX12 真实程序；不能只测 CreateDevice |
| P1 | Mono/Gecko、VC++、.NET、媒体和输入 | 在标准路径及长路径的干净容器逐项运行程序，视频有音画验证，输入/麦克风/手柄有实际用例 |
| P1 | 按游戏/版本/引擎的兼容 profile | 以证据维护 DLL override、后端、字体、启动参数和可回滚补丁，避免全部游戏共享一组 workaround |
| P2 | 游戏性能/稳定性验收 | 同场景平均 FPS、1% low、P95/P99 frame-time、冷/热 shader cache、30–60 分钟连续运行和崩溃率 |
| P2 | 分发与升级 | 干净机器安装、签名/公证、完整可再现构建、运行库版本锁定与升级回滚 |

独立产品路线需要实现或接入相应图形、媒体和兼容能力，并持续测试；不能从一次二进制检查承诺全产品严格 1:1。另一条本机路线是把已安装并授权的 CrossOver 作为外部运行后端，让 OpenGame 管理界面复用它的实际运行链；这能减少本机底层差异，但产品会依赖 CrossOver，且界面、启动配置和工作流仍需独立验收。本轮未接入该后端，也未复制其 D3DMetal 或私有配置数据库到 OpenGame 分发包。

## 验证状态

四组回归：Catalog、Shutdown、Archive、PerformanceSettings 均通过；性能设置另验证运行中后端/MSync 变更被拒绝且 catalog 保持原配置。完整原生启动器构建与签名验证通过。默认 macOS 27 SDK 缺少 SwiftUI 宏插件；用本机 SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk 完成构建，未改变系统开发工具选择。

尚未完成：真实游戏 FPS/长期稳定性、广泛视频编码、完整 DX12、用户历史格式报错复现、另一台 Mac 安装验收。因用户目前未安装 OpenGame，也没有具体错误样本，历史中断根因未确认。

## 核对使用的公开源码

DXMT v0.80 配置解析：https://github.com/3Shain/dxmt/blob/v0.80/src/util/config/config.cpp
Wine 11 Mono 路径发现：https://github.com/wine-mirror/wine/blob/wine-11.0/dlls/mscoree/metahost.c
Wine 11 组件安装：https://github.com/wine-mirror/wine/blob/wine-11.0/dlls/appwiz.cpl/addons.c
这些用于核对配置机制与查找流程；发布包的实际二进制和实验结果仍是本次结论的主要证据。
