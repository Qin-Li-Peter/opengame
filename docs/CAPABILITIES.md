# OpenGame 与 CrossOver 能力矩阵

| 能力 | OpenGame 0.5.2 历史基线 | 验收边界 |
| --- | --- | --- |
| 完整运行核心 | 已实现完整 APP 打包，基础 Wine 与 DXMT 使用各自严格匹配的核心，DXVK 使用增量包 | 干净 HOME 可创建 DXMT 容器；仍需第二台实体 Mac 下载验收 |
| 安装配方 | 自有 JSON 配方：Steam、VC++ 2015–2026、.NET 4.8 | 官方 HTTPS + SHA-256；没有复制 CrossOver 数据库，厂商更新后需更新哈希 |
| D3D10/11 | DXMT 0.80 与 DXVK 增量包 | 《渔力全开》DXMT 主菜单和输入已验证；不能外推所有游戏 |
| D3D12 | Wine/VKD3D 的 `D3D12CreateDevice` x64 探针返回 `S_OK` | 尚无真实 DX12 游戏通过；未达到 CrossOver D3DMetal 水平 |
| D3DMetal | 未捆绑 | Apple 组件不属于 CrossOver FOSS 源码，只有取得合法再分发授权后才能加入发布包 |
| VC++ / .NET / 字体 | VC++ 与 .NET 可一键下载安装；完整包自动配置 Liberation 替代字体 | 逐游戏仍需验证；不分发 Microsoft 专有字体 |
| 容器归档/恢复 | `.opengamebottle` 导出、路径检查、恢复、跨用户路径重写 | 容器外的游戏目录保持外部引用，不嵌入归档 |
| 视频解码 | 白名单 GStreamer 1.28.1 播放库及 Wine x86_64/i386 桥接已集成 | OpenH264→VideoToolbox 流水线与 64/32 位 DLL 装载通过；其它编码格式和真实游戏过场仍需逐项验证 |
| 签名和公证 | 脚本和 GitHub Release 工作流已实现 | 需要仓库所有者的 Developer ID 与 App Store Connect API 凭据才能产出正式签名包 |
| 全新 Mac 安装 | 自动化干净 HOME 验收已实现 | 仍需在另一台无开发环境的 Apple Silicon Mac 验证 Gatekeeper、Steam 和至少一款游戏 |

性能方面，已有微基准显示 OpenGame FOSS DXMT + MSync 与当时测试的 CrossOver DXMT + MSync 四项中位数相差约 5% 以内。微基准不能证明整款游戏 FPS、视频、输入、联网或稳定性等效，因此项目不宣称已与 CrossOver 全面打平。

## 0.5.8 独立开发版增量

- Steam：兼容模式为默认，标准模式作为实验选项；仅恢复同容器官方备份，可配置覆盖层，原生进程检测按 prefix/核心隔离，冷启动排除历史登录记录。兼容模式登录、官方下载更新与游戏下载已在本机验收；标准模式与覆盖层仍待验证。
- UI：图形选项为自动/D3DMetal/DXMT/DXVK/Wine；D3DMetal 禁用并明确未实现。提供 DLSS、MSync、高分辨率、帧率、Steam 模式与详细日志控制。
- DLSS：匹配 DXMT 0.80 的开源 NVAPI/NGX 转换模块，可选启用；NVAPI/NGX 初始化与参数分配通过。未验证超分辨率图像或游戏效果，不能宣称所有 DLSS 功能已实现。
- 格式：23 种非视频纹理、SRV/DSV 与 RGBA8 RTV/UAV 通过，2x/4x MSAA 通过，8x 未声明支持；NV12/YUY2 尚未支持。D3D11 设备请求 11_1 成功。
- D3D11：着色器正确像素读回、180 次窗口 Present 均通过。
- D3D12：独立 Wine 后端的队列、清屏、状态屏障、复制、fence 与像素读回通过；DXMT 后端不提供 D3D12，检测前需切换 Wine。尚未覆盖 DXIL 着色器或实际 DX12 游戏。
- 图形后端切换：切回 Wine 恢复原始 DLL，渲染器写入采用原子替换，避免留存 DXMT/DXVK DLL。

仍未达到全功能/真实游戏性能 1:1。新增运行时扩展不依赖已安装的 CrossOver，不捆绑 D3DMetal。
