# 运行核心

完整 APP 的 `Contents/Resources/Runtime` 使用以下结构：

```text
Engines/WineFOSS11/             一份 Wine 11 + MSync 核心
Engines/Support/                GStreamer 等共享运行库
RendererPacks/dxmt/             DXMT 的 32/64 位 d3d10core、d3d11、dxgi
RendererPacks/dxvk/             DXVK 的 32/64 位 d3d10core、d3d11、dxgi
manifest.json
provenance.json
```

OpenGame 优先使用 APP 内核心。开发版没有内置核心时，回退到 `~/Library/Application Support/OpenGame`。旧 WineHQ 容器仍能读取，但所有新容器使用 Wine FOSS 11。

创建或切换容器后，OpenGame 将所选渲染器的六个 DLL 原子安装到容器，并把原文件保存在 `.opengame-renderer-backup`。Steam CEF 使用 Wine 图形路径，游戏按容器选择加载 DXMT 或 DXVK。三个后端不再各自复制完整 Wine 树。

打包过程先运行 `relocate-runtime.py`，把构建目录和 `/opt/local` RPATH 改为 `@loader_path` 或 `@executable_path`，随后由 `audit-runtime.py` 拒绝绝对依赖、逃逸符号链接及私人运行状态。当前核心来自 CodeWeavers 26.3.0 公布的 FOSS 源码；归档哈希、构建开关和已测状态见 `provenance.json` 与 `runtime/BUILDING.md`。

Wine 已针对同包的 GStreamer 1.28.1 重新编译。完整包包含 `winegstreamer.so`、x86_64/i386 `winegstreamer.dll` 和经过白名单筛选的播放插件；GPL、受限专利、DVD、Python、GTK、采集、编辑和开发组件不会进入分发包。打包审计会拒绝缺少桥接模块的运行时。全新安装测试会用 OpenH264 生成测试流、经 Apple VideoToolbox 解码，并从 64 位和 32 位 Windows 探针加载 `winegstreamer.dll`。这证明 H.264 硬件解码路径和 Wine 桥接可装载，但尚未覆盖每种编码格式或真实游戏过场。Wine/VKD3D 的 x64 `D3D12CreateDevice` 探针已返回 `S_OK`，但尚未通过真实 DX12 游戏验收，不能视为与 D3DMetal 等效。
