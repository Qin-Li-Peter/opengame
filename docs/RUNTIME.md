# 运行核心

当前用户 Application Support/OpenGame/Engines 下的目录约定：

| 家族 | Wine | DXVK | DXMT |
| --- | --- | --- | --- |
| 旧容器兼容核心 | WineHQ11 | WineHQ11-DXVK | WineHQ11-DXMT |
| 默认核心 | WineFOSS11 | WineFOSS11-DXVK | WineFOSS11-DXMT |

每个核心具有 bin/wine、bin/wineserver、lib/wine 等标准目录。DXMT 还需要匹配的 winemetal.dll/winemetal.so 和 Wine 的 macdrv_functions 窗口接口。仅把几个图形 DLL 放入 WineHQ 核心不保证游戏窗口可用。Mono/Gecko 与图形后端也需匹配。旧视频支持目录是 Engines/Support/GStreamer.framework/Versions/1.0，FOSS Wine 尚未编入 GStreamer。

默认核心来自 CodeWeavers 26.3.0 的公开 FOSS Wine 源码，独立构建为 x86-64 loader 与 Windows WoW64 DLL，再接入独立 DXMT。源归档哈希和已测功能见 provenance.json。核心使用本机独立 WineHQ 构建的 x86-64 动态依赖，当前尚未完成这些依赖的可移植发布自动化。

`local-foss-build-reference.sh` 是此前已执行构建的参考配方，依赖旧研究工作目录、原 WineHQ 动态库和解压源码，不是克隆本仓库后就能执行成功的安装器。它记录了 Xcode/Clang、LLVM-MinGW、Bison、FreeType、GnuTLS 头文件与库，以及 MSync 所需构建方式。

本机修正过：GnuTLS dylib install name、Unix 模块 rpath、wineserver 的 libinotify 查找路径；补编 bcrypt、crypt32、secur32 和 ntdll 后通过 HTTPS 验证。Windows 核心来源归档见 https://www.codeweavers.com/crossover/source 。完整核心构建 CI 与引擎安装器是后续分发工作，当前 Actions 仅构建启动器。
