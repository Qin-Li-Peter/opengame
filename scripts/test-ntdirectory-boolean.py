#!/usr/bin/env python3
"""Bounded Windows x64 BOOLEAN regression using an isolated Wine prefix."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('app',type=Path)
parser.add_argument('--engine',choices=['WineFOSS11','WineFOSS11-DXMT'],default='WineFOSS11-DXMT')
parser.add_argument('--output',type=Path,default=Path('build/ntdirectory-validation'))
parser.add_argument('--cc',default=os.environ.get('OG_MINGW_CC','x86_64-w64-mingw32-gcc'))
args=parser.parse_args()
repository=Path(__file__).resolve().parent.parent
runtime=args.app.resolve()/'Contents/Resources/Runtime/Engines'/args.engine/'bin'
if not all((runtime/n).is_file() for n in ['wine','wineserver']):parser.error('app must contain the selected complete Wine runtime')
args.output.mkdir(parents=True,exist_ok=True)
output=Path(tempfile.mkdtemp(prefix='run-',dir=args.output.resolve()))
prefix=output/'prefix';prefix.mkdir()
assert prefix.parent==output
env=os.environ.copy()
for k in list(env):
    if k.startswith(('WINE','CX_','DYLD_','DXMT_','DXVK_')):env.pop(k)
env.update(WINEPREFIX=str(prefix),WINEDEBUG='-all',WINEMSYNC='1',WINEDLLOVERRIDES='winemenubuilder.exe=')
support=args.app.resolve()/'Contents/Resources/Runtime/Engines/Support/GStreamer.framework/Versions/1.0/lib'
env['DYLD_FALLBACK_LIBRARY_PATH']=str(support)+':'+str(runtime.parent/'lib')+':/usr/lib'
records=[]
def run(name,command,seconds):
    with (output/(name+'.stdout.txt')).open('w') as out,(output/(name+'.stderr.txt')).open('w') as err:
        p=subprocess.Popen(command,env=env,stdin=subprocess.DEVNULL,stdout=out,stderr=err)
        timed_out=False
        try:code=p.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            timed_out=True;p.kill();code=p.wait(timeout=5)
    records.append({'step':name,'pid':p.pid,'exit':code,'timed_out':timed_out})
    return code
failed=False
try:
    compiler=shutil.which(args.cc)
    if not compiler:raise RuntimeError('Windows x64 compiler not found; set OG_MINGW_CC')
    exe=output/'ntdirectory-boolean.exe'
    source=repository/'tests/diagnostics/ntdirectory-boolean.c'
    bridge=repository/'tests/diagnostics/ntdirectory-boolean-call.S'
    if run('compile',[compiler,'-O2','-Wall','-Wextra','-Werror',str(source),str(bridge),'-o',str(exe)],30):
        failed=True
    elif run('initialize',[str(runtime/'wine'),'wineboot','-u'],45):
        failed=True
    elif run('boolean',[str(runtime/'wine'),str(exe),'--expect-normalized'],20):
        failed=True
except Exception:
    failed=True
    raise
finally:
    # Only the fresh prefix created above is selected. Never stop a user bottle.
    run('stop-isolated-server',[str(runtime/'wineserver'),'-k'],5)
    if run('wait-isolated-server',[str(runtime/'wineserver'),'-w'],5):failed=True
    (output/'result.json').write_text(json.dumps({'runtime':str(runtime),'prefix':str(prefix),'steps':records,'passed':not failed},indent=2)+'\n')
    print(output)
raise SystemExit(1 if failed else 0)
