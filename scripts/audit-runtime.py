#!/usr/bin/env python3
"""Reject non-portable or private files from an OpenGame runtime payload."""
from pathlib import Path
import os, plistlib, subprocess, sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "build/OpenGame.app/Contents/Resources/Runtime").resolve()
if not (root / "Engines/WineFOSS11/bin/wine").is_file():
    raise SystemExit(f"missing Wine runtime: {root}")

required_video = (
    "Engines/WineFOSS11/lib/wine/x86_64-unix/winegstreamer.so",
    "Engines/WineFOSS11/lib/wine/x86_64-windows/winegstreamer.dll",
    "Engines/WineFOSS11/lib/wine/i386-windows/winegstreamer.dll",
    "Engines/Support/GStreamer.framework/Versions/1.0/bin/gst-inspect-1.0",
)
for relative in required_video:
    if not (root / relative).is_file():
        raise SystemExit(f"missing video runtime component: {relative}")

required_dxmt = (
    "Engines/WineFOSS11-DXMT/bin/wine",
    "Engines/WineFOSS11-DXMT/bin/wineserver",
    "Engines/WineFOSS11-DXMT/lib/wine/x86_64-unix/winemetal.so",
    "Engines/WineFOSS11-DXMT/lib/wine/x86_64-unix/winegstreamer.so",
    "Engines/WineFOSS11-DXMT/lib/wine/x86_64-windows/winemetal.dll",
)
for relative in required_dxmt:
    if not (root / relative).is_file():
        raise SystemExit(f"missing complete DXMT runtime component: {relative}")

forbidden_names = {"steam.exe", "loginusers.vdf", "libraryfolders.vdf", "library.json", "system.reg", "user.reg"}
forbidden_fragments = ("CrossOver.app", "/Prefixes/", "/drive_c/Program Files (x86)/Steam/")
problems = []
machos = []
for path in root.rglob("*"):
    if path.is_symlink():
        target = os.readlink(path)
        resolved = (path.parent / target).resolve()
        if target.startswith("/") or not resolved.is_relative_to(root):
            problems.append(f"escaping symlink: {path.relative_to(root)} -> {target}")
        continue
    if not path.is_file():
        continue
    if path.name.lower() in forbidden_names:
        problems.append(f"private/runtime-state file: {path.relative_to(root)}")
    try:
        header = path.read_bytes()[:4]
    except OSError as exc:
        problems.append(f"unreadable: {path}: {exc}")
        continue
    if header in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
        machos.append(path)

allowed = ("/System/Library/", "/usr/lib/")
for path in machos:
    linked = subprocess.run(["/usr/bin/otool", "-L", str(path)], text=True, capture_output=True, check=True).stdout
    for line in linked.splitlines()[1:]:
        if " (architecture " in line:
            continue
        dep = line.strip().split(" (", 1)[0]
        if dep.startswith("/") and not dep.startswith(allowed):
            problems.append(f"absolute dependency: {path.relative_to(root)} -> {dep}")
        if any(fragment in dep for fragment in forbidden_fragments):
            problems.append(f"private dependency: {path.relative_to(root)} -> {dep}")
    load = subprocess.run(["/usr/bin/otool", "-l", str(path)], text=True, capture_output=True, check=True).stdout.splitlines()
    for index, line in enumerate(load):
        if line.strip() == "cmd LC_RPATH" and index + 2 < len(load):
            value = load[index + 2].strip().removeprefix("path ").split(" (offset", 1)[0]
            if value.startswith("/") and not value.startswith(allowed):
                problems.append(f"absolute rpath: {path.relative_to(root)} -> {value}")

if problems:
    print("Runtime audit failed:", file=sys.stderr)
    print("\n".join(f"- {problem}" for problem in problems), file=sys.stderr)
    raise SystemExit(1)
print(f"Runtime audit passed: {len(machos)} Mach-O files, no private state or non-system absolute dependencies")
