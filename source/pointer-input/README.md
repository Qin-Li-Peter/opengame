# OpenGame Unity 鼠标输入适配

`input.c` 与 `version.def` 为本项目的 MIT 实现。面向当前测试的 Windows x64 Unity 6 Mono 游戏。只重定向当前进程内 UnityPlayer.dll 的五项输入导入：EnableMouseInPointer、IsMouseInPointerEnabled、GetPointerInfo、GetPointerType、GetPointerDevices。通过 Windows 线程消息钩子将传统鼠标事件转换成指针事件；原版版本信息接口仍转发到系统 version.dll。没有修改游戏或 Wine 的磁盘机器指令，也没有修改其他进程。

研究时参考了 [ptrshim 的问题说明](https://github.com/feiyuehchen/Meccha-Chameleon-For-MAC/blob/2bf0c1779f0982280d04774e9ea675e7f33df783/ptrshim/README.md)，它缺少可确认的代码许可证，因此未将该项目的 DLL 或源码加入本安装包。本实现改用 UnityPlayer 导入表，不使用它的内联指令补丁。

构建：

```sh
"$OG_MINGW_CC" -O2 -Wall -Wextra -Werror -shared input.c version.def -o version.dll -luser32 -lkernel32
```

安装采用 `install.py`，参数为 OpenGame 容器内的游戏 EXE。先退出目标游戏。遇到已有不同 version.dll 会拒绝覆盖；只在该 EXE 的 Wine AppDefaults 中设置 version=native,builtin。已验证《渔力全开》使用的输入接口，不保证适用于所有 Unity 版本。

卸载时先退出游戏，移走游戏目录内与本包 SHA256 相同的 version.dll，并恢复 install.json 中记录的原 AppDefaults version 覆盖。不要移除任意同名 DLL。
