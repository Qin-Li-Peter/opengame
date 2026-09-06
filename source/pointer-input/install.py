#!/usr/bin/env python3
"""Install the OpenGame input adapter for one stopped x64 Unity game."""
import argparse,datetime,hashlib,json,os,re,shutil,subprocess
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('game_exe',type=Path);args=parser.parse_args()
root=Path.home()/'Library/Application Support/OpenGame';game=args.game_exe.resolve()
prefix_root=(root/'Prefixes').resolve()
try:relative=game.relative_to(prefix_root)
except ValueError:raise SystemExit('Choose a game inside an OpenGame prefix.')
if len(relative.parts)<3 or relative.parts[1]!='drive_c' or not game.is_file():raise SystemExit('Invalid game location.')
raw=game.read_bytes()
pe=int.from_bytes(raw[60:64],'little') if len(raw)>=64 else len(raw)
if raw[:2]!=b'MZ' or raw[pe:pe+4]!=b'PE\0\0' or raw[pe+4:pe+6]!=b'\x64\x86':raise SystemExit('This adapter requires a Windows x64 EXE.')
prefix=prefix_root/relative.parts[0];folder=game.parent
if not (folder/'UnityPlayer.dll').is_file():raise SystemExit('UnityPlayer.dll was not found next to the EXE.')
processes=subprocess.check_output(['/bin/ps','-axo','comm='],text=True).splitlines()
if str(game) in processes:raise SystemExit('Exit this game before installing its input adapter.')
source=Path(__file__).resolve().parents[2]/'build/OpenGame.app/Contents/Resources/PointerInput/version.dll'
data=source.read_bytes();digest=hashlib.sha256(data).hexdigest();target=folder/'version.dll'
if target.exists() and target.read_bytes()!=data:raise SystemExit('A different version.dll exists; preserved without changes.')
catalog=json.loads((root/'library.json').read_text())
bottle=next((b for b in catalog['bottles'] if b['directory']==f'Prefixes/{relative.parts[0]}'),None)
if bottle is None:raise SystemExit('The game container is not registered in OpenGame.')
family='WineFOSS11' if bottle.get('engineFamily')=='foss' else 'WineHQ11'
suffix={'wine':'','dxvk':'-DXVK','dxmt':'-DXMT'}[bottle['renderer']]
engine=root/'Engines'/(family+suffix)
if not (engine/'bin/wine').is_file():raise SystemExit(f'OpenGame runtime is missing: {engine}')
env={k:v for k,v in os.environ.items() if not k.startswith(('WINE','CX_','DYLD_','DXVK_','DXMT_'))}
env.update(WINEPREFIX=str(prefix),WINEDEBUG='-all',WINEDLLOVERRIDES='winemenubuilder.exe=',DYLD_FALLBACK_LIBRARY_PATH=str(engine/'lib')+':/usr/lib')
key='HKCU\\Software\\Wine\\AppDefaults\\'+game.name+'\\DllOverrides'
def registry(*values):
    return subprocess.run([str(engine/'bin/wine'),'reg',*values],env=env,capture_output=True,timeout=30)
query=registry('query',key,'/v','version')
if query.returncode not in (0,1):raise SystemExit('Cannot read existing Wine override.')
match=re.search(r'version\s+REG_SZ\s+([^\r\n]+)',query.stdout.decode(errors='replace'),re.I)
backup=root/'Backups/InputFix'/datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f');backup.mkdir(parents=True)
record={'game':str(game),'dll_sha256':digest,'original_version_override':match.group(1).strip() if match else None,'dll_already_present':target.exists()}
(backup/'install.json').write_text(json.dumps(record,ensure_ascii=False,indent=2))
if not target.exists():shutil.copy2(source,target)
result=registry('add',key,'/v','version','/d','native,builtin','/f')
if result.returncode:
    if not record['dll_already_present']:target.rename(backup/'version.dll')
    raise SystemExit('Wine override failed; new DLL rolled back.')
print('Installed game-local input adapter:',game.name)
print('Recovery record:',backup/'install.json')
