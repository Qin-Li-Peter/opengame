> 这是 2026-10-13 的历史开发记录；当前发布与测试范围以 Release notes 为准。

OpenGame 0.5.8 独立对齐开发进展（未发布）
2026-10-13

本轮按独立产品路线实现，不接入 CrossOver 作为运行后端。参考了本机 CrossOver 高级设置的实际选项；新增运行模块来自与现有核心匹配的 DXMT 0.80 官方公开包。

已实现
- 图形菜单顺序：自动、D3DMetal、DXMT、DXVK、Wine。D3DMetal 实际禁用，不可误选；UI 验收发现 SwiftUI Picker 子项 disabled 无效，已改为真正禁用的 Menu 按钮。
- DLSS、MSync、高分辨率模式与帧率上限控制；不可用能力禁用。高分辨率通过 Wine Mac Driver RetinaMode 写入，DLSS 通过匹配 NGX/NVAPI 到 MetalFX 的转换模块及 DXMT_ENABLE_NVEXT 生效。
- Steam 两种模式：兼容模式保留为默认；标准模式作为实验选项。标准模式停止包装器监控、移除兼容启动参数，并恢复同容器的官方程序。没有备份时拒绝恢复，绝不取其他容器的程序替换。
- Steam 覆盖层、详细兼容日志可配置；冷启动登录检查排除旧会话，只读末尾 512 KiB；原生 Steam/游戏进程按核心与 prefix 过滤，避免识别到其他容器或 CrossOver 的进程。
- 设置异步保存，显示进度；保存期间不启动游戏。容器配置使用文件锁，渲染器写入原子替换；切回 Wine 恢复原始 D3D DLL；扩展关闭时恢复原有 DLL。
- Internet 设置、模拟重启、图形格式检测、DLSS 初始化检测、DirectX 12 读回检测入口；新增单容器正常退出/强制结束，回归验证不查询或终止其他容器。
- 所有可选设置随复制和归档恢复保留，旧 catalog 默认不改变既有行为。

实测
- D3D11 feature level 11_1 设备创建通过。
- 23 种非视频纹理创建通过，25 项 SRV/DSV/RTV/UAV 视图创建通过。
- 2x/4x MSAA 创建通过；8x 查询未声明支持，未强行创建。
- 多线程创建和命令列表能力查询通过。
- DXMT NVAPI Initialize、NGX Init、能力参数分配通过；最终完整 APP 的 CLI probe 再验退出码 0。
- D3D11 着色器编译、执行和正确像素读回通过；窗口 SwapChain 创建和 180 次 Present S_OK 通过。
- 独立 Wine 后端 D3D12 device、queue、RTV clear、barrier、copy、fence、map/readback 全流程通过，RGBA=0,255,0,255。
- 在 DXMT 后端运行 D3D12 则得到 E_NOINTERFACE。这是后端选择差异，新增检测仅在 Wine 后端可用，避免误导为 DXMT 支持 DX12。
- UI 实机验证：D3DMetal 禁用；DLSS/高分辨率可以打开；保存显示进度并成功返回主界面；持久化值回读 true，高分辨率注册表回读 RetinaMode=Y；启用后 DLSS 检测菜单可用。
- 五组回归通过；完整 APP 构建、签名校验通过；运行库审计通过（569 个 Mach-O，无私人状态或非系统绝对依赖）。构建用本机 macOS 26.5 SDK，未修改系统开发工具选择。

明确未完成
- 整体功能、所有游戏性能和稳定性 1:1。
- 全部容器管理交互对齐，例如任意命令编辑与删除/还原容器界面。
- D3DMetal；当前不可选，不借用 CrossOver 文件。
- DLSS 超分辨率图像、质量、帧率和帧生成；只验 API 初始化，不能据此声称游戏 DLSS 完整可用。
- 标准 Steam 模式实际登录、商店/下载、自动更新、多进程 CEF、覆盖层的完整验收。因此尚未设为默认。
- NV12/YUY2 视频纹理、广泛编码与游戏过场兼容。
- DX12 着色器/DXIL、完整游戏及长期稳定性；32x32 清屏读回是基础正确性测试。
- 自动模式的逐游戏 API 判定；目前根据已安装核心优先 DXMT，DX12 需明确选择 Wine。
- 真实游戏平均 FPS、1% low、P95/P99 frame-time、冷/热缓存和 30–60 分钟连续运行。

构建产物
完整独立开发版：build/OpenGame.app
本轮未安装到 Applications，未上传发布。若要自行使用，先移至短路径的 Applications 目录；过深路径曾触发 Mono 的 MAX_PATH 限制。
本次 UI 与图形运行均在隔离测试容器，未修改日常 CrossOver 容器。

后续优先级
1. Steam 标准模式真实客户端验收，定位 CEF 多进程图形/网络兼容；未通过前保留兼容模式默认。
2. 为 NV12/YUY2 建立 plane/decoder 路径与真实视频测试，再按差分结果修改 DXMT/Wine 实现。
3. DLSS 实际 EvaluateFeature、图像读回及真实游戏验证。
4. DX12 着色器、交换链和游戏场景测试，建立按游戏版本的兼容 profile。
5. 真实游戏的帧时间和稳定性对照，再确定针对性性能优化。

源码参考
https://github.com/3Shain/dxmt/blob/v0.80/src/nvngx/nvngx.cpp
https://github.com/3Shain/dxmt/blob/v0.80/src/dxgi/dxgi.cpp
https://github.com/3Shain/dxmt/blob/v0.80/LICENSE
NVIDIA nvapi.h 对应的头文件保留 MIT 通知，licenses/NVIDIA-NVAPI-MIT.txt 随包提供。
