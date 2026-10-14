#!/usr/bin/env python3
"""Read-only binary inventory; writes only the requested JSON report.
No application execution, installation, global config, or bottle modification.
"""
import argparse,hashlib,json,subprocess
from pathlib import Path

def inventory(app):
    root=app/'Contents'
    files=[]
    for folder in [root/'MacOS',root/'Resources/Runtime/Engines',root/'SharedSupport/CrossOver']:
        if not folder.exists():continue
        for p in folder.rglob('*'):
            if p.is_file() and p.name in {'OpenGame','OpenGameCLI','CrossOver','wine','wineloader','wineserver','ntdll.so','winemac.so','winemetal.so','d3d11.dll','dxgi.dll','D3DMetal','libMoltenVK.dylib','winegstreamer.so'}:
                files.append(p)
    result={}
    for p in sorted(set(files)):
        result[str(p.relative_to(root))]={
            'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),
            'type':subprocess.check_output(['file','-b',str(p)],text=True).strip(),
            'dependencies':subprocess.run(['otool','-L',str(p)],capture_output=True,text=True).stdout.splitlines()[1:]}
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--opengame',required=True,type=Path)
    parser.add_argument('--crossover',type=Path,default=Path('/Applications/CrossOver.app'))
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    for p in [args.opengame,args.crossover]:
        if not (p/'Contents/Info.plist').is_file():parser.error(f'Not an app bundle: {p}')
    report={'scope':'Static binary identity and dependencies; no FPS or compatibility inference',
            'opengame':inventory(args.opengame),'crossover':inventory(args.crossover)}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2))
    print(f'Wrote {args.output}; {len(report["opengame"])} OpenGame and {len(report["crossover"])} CrossOver entries')
if __name__=='__main__':main()
