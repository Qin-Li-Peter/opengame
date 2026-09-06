# 第三方来源与分发边界

| 组件 | 来源与许可证 | 本仓库/CI 是否包含其二进制 |
| --- | --- | --- |
| Steam CEF 参数包装器 | notpop/steam-on-m1-wine，MIT；提交见 source/steam-wrapper/source.json | 包含从对应 C 源码构建的包装器；不包含 Valve 原程序 |
| Wine FOSS | CodeWeavers 公布的 Wine 源码，LGPL-2.1-or-later，具体以源码文件为准 | Git 仓库不含；完整 Release APP 可包含并同时提供对应源码包 |
| WineHQ macOS 构建 | Gcenx/macOS_Wine_builds；Wine 与其依赖分别许可 | 不包含 |
| DXMT 0.80 | 3Shain/dxmt，该版本 MIT；未集成 nvapi64.dll/nvngx.dll | Git 仓库不含；完整 Release APP 可包含六个渲染 DLL |
| DXVK 1.10.3 兼容构建 | CodeWeavers FOSS 源归档；zlib 许可证 | Git 仓库不含；完整 Release APP 可包含六个渲染 DLL |
| GStreamer 1.28.1 / OpenH264 2.6.0 | GStreamer LGPL-2.1-or-later；OpenH264 BSD-2-Clause | 完整 Release APP 只装载白名单播放组件和 Wine 桥接；排除命名为 GPL/restricted/DVD 的组件，对应源归档随源码包提供 |
| Liberation Fonts 2.1.5 | liberationfonts；SIL OFL 1.1 | 完整 Release APP 可包含，并自动安装为 Arial/Times/Courier 的替代字体 |
| LLVM-MinGW | mstorsjo/llvm-mingw，编译器及运行库各自许可 | CI 下载构建工具；辅助程序链接所需运行库通知保留于 licenses/MinGW-* 和 LLVM 许可证 |

许可证副本见 licenses。`package-full.sh` 会把固定哈希的 CodeWeavers FOSS、DXMT、GStreamer、OpenH264、字体与构建配方放入独立对应源码包；GStreamer wrap 引用的全部源归档也会逐个校验并收录。原创 OpenGame 的 MIT 许可证不会覆盖第三方组件。

不得将本地 Steam 会话、游戏、模组、个人图标、存档或 CrossOver 专有运行组件添加到发布包。用户可通过 OpenGame 添加自己拥有的游戏，图标从自己的游戏文件提取。
