#!/usr/bin/env python3
"""Rewrite build-machine Mach-O paths so a runtime can move with OpenGame.app."""
from pathlib import Path
import os, subprocess, sys

root = Path(sys.argv[1]).resolve()
machos = []
for path in root.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    try:
        magic = path.read_bytes()[:4]
    except OSError:
        continue
    if magic in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
        machos.append(path)

allowed = ("/System/Library/", "/usr/lib/")
for path in machos:
    changes = []
    linked = subprocess.run(["/usr/bin/otool", "-L", str(path)], text=True, capture_output=True, check=True).stdout
    deps = [line.strip().split(" (", 1)[0] for line in linked.splitlines()[1:] if " (architecture " not in line]
    own_ids = subprocess.run(["/usr/bin/otool", "-D", str(path)], text=True, capture_output=True, check=False).stdout.splitlines()[1:]
    own_id = own_ids[0].strip() if own_ids else None
    if own_id and own_id.startswith("/") and not own_id.startswith(allowed):
        changes += ["-id", "@rpath/" + path.name]
    for dep in deps:
        if dep == own_id:
            continue
        if dep.startswith("/") and not dep.startswith(allowed):
            candidates = list(root.rglob(Path(dep).name))
            if not candidates:
                raise SystemExit(f"cannot relocate missing dependency: {path.relative_to(root)} -> {dep}")
            changes += ["-change", dep, "@rpath/" + Path(dep).name]

    load = subprocess.run(["/usr/bin/otool", "-l", str(path)], text=True, capture_output=True, check=True).stdout.splitlines()
    rpaths = []
    for index, line in enumerate(load):
        if line.strip() == "cmd LC_RPATH" and index + 2 < len(load):
            rpaths.append(load[index + 2].strip().removeprefix("path ").split(" (offset", 1)[0])
    for value in rpaths:
        if value.startswith("/"):
            changes += ["-delete_rpath", value]

    relative = path.relative_to(root).as_posix()
    if "/bin/" in relative:
        wanted = "@executable_path/../lib"
    elif "/lib/wine/" in relative:
        wanted = "@loader_path/../.."
    else:
        wanted = "@loader_path"
    if wanted not in rpaths:
        changes += ["-add_rpath", wanted]
    if changes:
        result=subprocess.run(["/usr/bin/install_name_tool", *changes, str(path)], text=True, capture_output=True)
        if result.returncode:
            raise SystemExit(f"install_name_tool failed for {path.relative_to(root)}:\n{result.stderr}")

print(f"Relocated {len(machos)} Mach-O files")
