# 第三方来源与分发边界

| 组件 | 来源与许可证 | 本仓库/CI 是否包含其二进制 |
| --- | --- | --- |
| Steam CEF 参数包装器 | notpop/steam-on-m1-wine，MIT；提交见 source/steam-wrapper/source.json | 包含从对应 C 源码构建的包装器；不包含 Valve 原程序 |
| Wine FOSS | CodeWeavers 公布的 Wine 源码，LGPL-2.1-or-later，具体以源码文件为准 | 不包含 |
| WineHQ macOS 构建 | Gcenx/macOS_Wine_builds；Wine 与其依赖分别许可 | 不包含 |
| DXMT 0.80 | 3Shain/dxmt，该版本 MIT；未集成 nvapi64.dll/nvngx.dll | 不包含 |
| DXVK | 来源记录见 components.json；各文件按自身许可证 | 不包含 |
| LLVM-MinGW | mstorsjo/llvm-mingw，编译器及运行库各自许可 | CI 下载构建工具；辅助程序链接所需运行库通知保留于 licenses/MinGW-* 和 LLVM 许可证 |

许可证副本见 licenses。引用依赖版本和来源不是对完整分发材料已经齐全的保证。将来将 LGPL 二进制打包分发时，应同时满足其完整对应源码与构建材料要求；其它依赖也需逐项核对。原创 OpenGame 的 MIT 许可证不会覆盖第三方组件。

不得将本地 Steam 会话、游戏、模组、个人图标、存档或 CrossOver 专有运行组件添加到发布包。用户可通过 OpenGame 添加自己拥有的游戏，图标从自己的游戏文件提取。
