#!/usr/bin/env python3
"""Stage matched DXMT 0.80 open-source NVAPI/NGX modules from a verified release archive."""
from pathlib import Path
import argparse,hashlib,tarfile,json
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('archive',type=Path);p.add_argument('runtime',type=Path)
a=p.parse_args()
expected='8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d'
if hashlib.sha256(a.archive.read_bytes()).hexdigest()!=expected:raise SystemExit('DXMT publisher archive SHA-256 mismatch')
manifest=json.loads((a.runtime/'manifest.json').read_text())
if not str(manifest['components']['dxmt']).startswith('0.80'):raise SystemExit('Extensions require the matching DXMT 0.80 runtime')
target=a.runtime/'Extensions/dxmt/x86_64-windows';target.mkdir(parents=True,exist_ok=True)
with tarfile.open(a.archive) as tar:
 for name in ['nvapi64.dll','nvngx.dll']:
  member=tar.getmember('v0.80/x86_64-windows/'+name)
  if not member.isfile():raise SystemExit('Not a regular DLL: '+name)
  data=tar.extractfile(member).read()
  if not data.startswith(b'MZ'):raise SystemExit('Invalid PE image: '+name)
  (target/name).write_bytes(data)
manifest['components']['dxmt_extensions']='0.80 NVAPI/NGX -> MetalFX; experimental D3D11 x64'
(a.runtime/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Staged matched DXMT NVAPI/NGX modules; real-game validation is separate')
