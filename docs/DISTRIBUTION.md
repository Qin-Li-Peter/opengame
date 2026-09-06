# 给朋友分发

推荐使用 GitHub Actions 自动编译，再将通过验收的安装包放到 GitHub Release。Actions 的 artifact 是暂存构建产物，Release 是版本下载入口；两者不是同一个东西。

默认 `build.yml` 构建启动器预览；`release.yml` 构建包含运行核心的完整 APP。后者要求一个已审计且哈希固定的运行时包，并要求 Developer ID 和 Apple 公证凭据。

## 私有仓库

有仓库读取权限的人才能访问其中的 Release。可以由仓库所有者邀请朋友为协作者。不要将私人访问令牌嵌入安装器或下载链接，也不要为了分享 Release 意外将整个仓库设为公开。仓库所有者也可下载包后自行发送；分发第三方运行组件时仍需满足其许可证要求。

## 完整试玩版的发布条件

- 在一台没有开发者目录、Steam 登录状态和旧引擎的 Mac 上完成安装验证。
- 安装程序下载校验过的合法引擎，或提供可分发的引擎包；新建空容器，由朋友自行安装并登录 Steam。
- 检查动态库依赖和绝对构建路径；离开开发机器仍能运行。
- 随第三方二进制提供对应许可证、版权通知和所需完整对应源码及构建材料。单独贴上游主页不能替代所有源码提供义务。
- 补齐 Developer ID 签名和公证，并实际验证下载后启动。
- 以 Pre-release 发布首批内测版，写明支持的 Mac、已测游戏和已知问题；包含安装包、SHA256SUMS、变更说明，以及对应源码材料。

当前已完成去重运行时打包、绝对依赖修复、对应源码包、配方、容器迁移和干净 HOME 验收。Apple 凭据和第二台干净实体 Mac 验收仍需仓库所有者完成。不要上传整个 `Application Support/OpenGame`，其中可能有账号、游戏和存档；`package-full.sh` 只选择 `Engines` 中的白名单文件并执行审计。

参考：[GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)、[GNU LGPL 2.1](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html)、[Apple 分发与公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。
