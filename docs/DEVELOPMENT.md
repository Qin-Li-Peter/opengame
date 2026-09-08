# 开发与构建

普通用户请从 [README](../README.md) 的下载入口安装完整应用。本页面向维护者。

## 本地构建启动器

需要 Apple Silicon Mac、Xcode Command Line Tools 和 LLVM-MinGW Windows 编译器。CI 固定编译器版本并校验 SHA256。

```sh
export OG_MINGW_CC=/path/to/llvm-mingw/bin/x86_64-w64-mingw32-gcc
scripts/test.sh
scripts/build.sh
scripts/package.sh
```

应用输出到 `build/OpenGame.app`，压缩包输出到 `dist/`。以上构建只有启动器，不带 Wine 运行库，不应作为普通用户安装包发布。

## 构建完整安装包

先按 [运行库构建说明](../runtime/BUILDING.md) 准备经过审计的独立运行库目录，包含完整基础核心、DXMT 核心、DXVK 文件和 GStreamer 支持文件。不要假定个人应用数据目录中的引擎齐全。

```sh
scripts/package-full.sh /path/to/audited-runtime-root
```

脚本审计依赖和个人数据，输出完整应用 ZIP、对应源码归档和 SHA256SUMS.txt。源码归档来自当前 Git HEAD，打包前应提交所需变更；不要移动已发布标签或覆盖现有安装包来掩盖代码变化。

签名、公证及发布条件见 [分发说明](DISTRIBUTION.md)。默认本地签名不等于 Developer ID 签名或 Apple 公证。

## 工作流与验证

- `.github/workflows/build.yml`：推送/PR 等触发的启动器构建。
- `.github/workflows/release.yml`：手动选择标签和已审核运行库的完整发布流程，需要 Apple 签名与公证凭据。
- `scripts/test.sh`：启动、退出和容器管理等回归测试。
- `scripts/test-fresh-install.sh APP`：隔离配置目录下的安装检查；设置 `OG_MINGW_CC` 才会运行可选 Windows 探测。0.5.7 默认 DXMT 的 D3D12 设备探测未通过，基础 Wine 引擎设备探测通过，不代表真实 DX12 游戏可用。

发行时应核对本地与 GitHub 附件的 SHA256。设备探测、编译和菜单可操作不能替代真实游戏、联机、语音和全新实体 Mac 验收。

## 进一步阅读

- [运行库布局](RUNTIME.md)
- [运行库来源与构建](../runtime/BUILDING.md)
- [第三方许可证](THIRD_PARTY.md)
- [能力与历史诊断](CAPABILITIES.md)
- [Steam 网络冻结诊断](STEAM-NETWORK-FREEZE.md)

CLI 位于应用包 `Contents/MacOS/OpenGameCLI`。用户数据默认位于 `~/Library/Application Support/OpenGame`；隔离测试使用 `OPENGAME_ROOT`，不要使用真实账号容器进行清理测试。
