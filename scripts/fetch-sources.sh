#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
destination=${1:-build/sources}
mkdir -p "$destination"
python3 - "$destination" <<'PY'
import hashlib,json,pathlib,sys,urllib.request
root=pathlib.Path(sys.argv[1])
for component in json.load(open('components.json')):
    if component.get('kind')!='source': continue
    target=root/component['file']
    if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest()!=component['sha256']:
        print('Downloading',component['url'],flush=True)
        with urllib.request.urlopen(component['url']) as response,target.open('wb') as output:
            while chunk:=response.read(1024*1024): output.write(chunk)
    actual=hashlib.sha256(target.read_bytes()).hexdigest()
    if actual!=component['sha256']: raise SystemExit(f'hash mismatch: {target}')
    print(actual,target)
PY
scripts/fetch-gstreamer-subprojects.py "$destination/gstreamer-1.28.1-source.tar.gz" "$destination/gstreamer-subprojects"
