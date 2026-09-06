#!/usr/bin/env python3
"""Install OpenGame's MIT CEF argument wrapper; archive only our obsolete UI DLLs."""
from pathlib import Path
import os, shutil, uuid
root = Path.home() / 'Library/Application Support/OpenGame'
source = Path(__file__).resolve().parents[1] / 'build/OpenGame.app/Contents/Resources/steamwebhelper.exe'
target = root / 'Engines/SteamCompat/steamwebhelper.exe'
target.parent.mkdir(parents=True, exist_ok=True)
temp = target.with_name('.wrapper-' + str(uuid.uuid4()))
shutil.copy2(source, temp)
os.replace(temp, target)
for prefix in ((root / 'Prefixes').iterdir() if (root / 'Prefixes').is_dir() else []):
    steam = prefix / 'drive_c/Program Files (x86)/Steam'
    folders = [steam]
    cef = steam / 'bin/cef'
    if cef.is_dir():
        folders.extend(p for p in cef.iterdir() if p.is_dir() and p.name.startswith('cef.'))
    for folder in folders:
        for name in ('dxgi.dll', 'd3d11.dll', 'd3d10core.dll'):
            dll = folder / name
            if dll.is_file() and not dll.is_symlink():
                with dll.open('rb') as f:
                    f.seek(64)
                    managed = f.read(16) == b'OpenGame DLL    '
                if managed:
                    backup = root / 'Backups/SteamUI-0.3.1' / prefix.name / dll.relative_to(steam)
                    backup.parent.mkdir(parents=True, exist_ok=True)
                    if backup.exists():
                        backup = backup.with_name(backup.name + '.' + str(uuid.uuid4()))
                    dll.rename(backup)
print('Steam compatibility component installed; Steam and games were not restarted.')
