#!/usr/bin/env python3
"""Remove Wine build paths without changing code, string offsets or exports.

Run strip -S first. Only known Wine installation-prefix and source-file strings
inside Mach-O __cstring sections are replaced with equal-length portable prefixes (padding preserves pooled suffixes). Unknown home
paths fail closed. Re-sign and run runtime tests after this packaging step.
"""
import argparse,json,re,struct,subprocess,shutil,hashlib,os
from pathlib import Path
def pe_identity(data):
 at=struct.unpack_from('<I',data,0x3c)[0];opt=at+24
 if data[at:at+4]!=b'PE\0\0':raise ValueError('Not PE')
 magic=struct.unpack_from('<H',data,opt)[0]
 if magic not in (0x10b,0x20b):raise ValueError('Unsupported PE optional header')
 count=struct.unpack_from('<H',data,at+6)[0];headers=opt+struct.unpack_from('<H',data,at+20)[0];sections=[]
 for i in range(count):
  off=headers+i*40;name=bytes(data[off:off+8]).split(b'\0')[0];vsize,rva,size,raw=struct.unpack_from('<4I',data,off+8);sections.append((name,vsize,rva,size,raw))
 def offset(rva):
  for _,vsize,start,size,raw in sections:
   if start<=rva<start+max(vsize,size):return raw+rva-start
  raise ValueError('Unmapped PE RVA')
 def string(rva):
  start=offset(rva);return bytes(data[start:data.index(0,start)])
 directory=opt+(96 if magic==0x10b else 112);exports=struct.unpack_from('<I',data,directory)[0];identity=[]
 if exports:
  off=offset(exports);base,nfunc,nname,func,names,ords=struct.unpack_from('<6I',data,off+16)
  if nfunc>100000 or nname>100000:raise ValueError('Oversized PE exports')
  identity.append((base,tuple(struct.unpack_from('<'+str(nfunc)+'I',data,offset(func))) if nfunc else ()))
  identity.append(tuple((string(struct.unpack_from('<I',data,offset(names)+i*4)[0]),struct.unpack_from('<H',data,offset(ords)+i*2)[0]) for i in range(nname)))
 text=tuple((name,rva,vsize,hashlib.sha256(data[raw:raw+vsize]).hexdigest()) for name,vsize,rva,size,raw in sections if name==b'.text')
 return (struct.unpack_from('<I',data,opt+16)[0],identity,text)

compiler=os.environ.get('OG_MINGW_CC','x86_64-w64-mingw32-gcc')
compiler_dir=Path(shutil.which(compiler) or compiler).parent
pe_strip=shutil.which('x86_64-w64-mingw32-strip') or (str(compiler_dir/'llvm-strip') if (compiler_dir/'llvm-strip').is_file() else 'llvm-strip')
p=argparse.ArgumentParser();p.add_argument('runtime',type=Path);p.add_argument('--report',type=Path);p.add_argument('--home',type=Path,default=Path.home());args=p.parse_args();changes=[]
pattern=re.escape((str(args.home)+'/').encode())+rb'[^\x00]*'
wide_needle=(str(args.home)+'/').encode('utf-16le')
if not (args.runtime/'manifest.json').is_file():p.error('Expected an OpenGame bundled runtime')
# Import archives are development inputs, never loaded by Wine games.
for engine in (args.runtime/'Engines').glob('WineFOSS11*'):
 headers=engine/'include'
 if headers.is_dir() and not headers.is_symlink():shutil.rmtree(headers)
 for name in ['winegcc','wineg++','winecpp','winecc','winedump','widl','wmc','winebuild','wrc']:
  tool=engine/'bin'/name
  if tool.is_file() or tool.is_symlink():tool.unlink()
for debug in args.runtime.rglob('*.dSYM'):
 if debug.is_dir() and not debug.is_symlink():shutil.rmtree(debug)
for archive in (args.runtime/'Engines').glob('WineFOSS11*/lib/wine/**/*.a'):
 if archive.is_file() or archive.is_symlink():archive.unlink()
for file in args.runtime.rglob('*'):
 if not file.is_file() or file.is_symlink():continue
 data=file.read_bytes()
 if not re.search(pattern,data) and wide_needle not in data:continue
 macho=data[:4]==b'\xcf\xfa\xed\xfe'
 pe=data[:2]==b'MZ'
 if not macho and not pe:raise SystemExit('Unsupported binary with home path: '+str(file))
 nm=['nm','-gjU'] if macho else [shutil.which('x86_64-w64-mingw32-nm') or 'llvm-nm','--extern-only','--defined-only']
 before=subprocess.check_output(nm+[str(file)],stderr=subprocess.DEVNULL) if macho else pe_identity(data)
 strip=['strip','-S'] if macho else [pe_strip,'--strip-debug']
 subprocess.run(strip+[str(file)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 data=bytearray(file.read_bytes());ranges=[]
 if macho:
  ncmds=struct.unpack_from('<I',data,16)[0];at=32
  for _ in range(ncmds):
   cmd,size=struct.unpack_from('<II',data,at)
   if cmd==0x19:
    count=struct.unpack_from('<I',data,at+64)[0]
    for i in range(count):
     off=at+72+i*80;name=bytes(data[off:off+16]).split(b'\0')[0]
     if name==b'__cstring':ranges.append((struct.unpack_from('<I',data,off+48)[0],struct.unpack_from('<Q',data,off+40)[0]))
   at+=size
 else:
  at=struct.unpack_from('<I',data,0x3c)[0]
  if data[at:at+4]!=b'PE\0\0':raise SystemExit('Unsupported DOS image with home path')
  count=struct.unpack_from('<H',data,at+6)[0];headers=at+24+struct.unpack_from('<H',data,at+20)[0]
  for i in range(count):
   off=headers+i*40;name=bytes(data[off:off+8]).split(b'\0')[0]
   if name==b'.rdata':ranges.append((struct.unpack_from('<I',data,off+20)[0],struct.unpack_from('<I',data,off+16)[0]))
 replaced=0
 for match in list(re.finditer(pattern,data)):
  start,end=match.span();original=match.group()
  if not any(a<=start and end<a+b for a,b in ranges) or data[end]!=0:raise SystemExit('Unexpected home path segment: '+str(file))
  marker=re.search(rb'/work/(?:cx-wine(?:-gst)?-stage|ntdll-candidate-stage)(/.*)$',original)
  source=re.search(rb'/crossover-foss/sources/wine/([^:\x00]*\.(?:c|h|y|l|yy|inc)(?::[^\x00]*)?)$',original)
  if marker:
   tail=marker.group(1);prefix_size=len(original)-len(tail);portable=b'/opt/opengame'
   extra=prefix_size-len(portable);padding=b'/.'*(extra//2) if extra%2==0 else b'/'+b'/.'*((extra-1)//2)
   replacement=portable+padding+tail
  elif source:
   tail=source.group(1);prefix_size=len(original)-len(tail);portable=b'/opt/opengame/src'
   extra=prefix_size-len(portable)-1;padding=b'/.'*(extra//2) if extra%2==0 else b'/'+b'/.'*((extra-1)//2)
   replacement=portable+padding+b'/'+tail
  else:raise SystemExit('Unknown Wine home path: '+str(file))
  if len(replacement)!=len(original):raise SystemExit('Replacement must preserve literal and suffix offsets')
  data[start:end]=replacement;replaced+=1
 cursor=0
 while True:
  start=data.find(wide_needle,cursor)
  if start<0:break
  end=start
  while end+2<=len(data) and data[end:end+2]!=b'\0\0':end+=2
  if end+2>len(data) or not any(a<=start and end+1<a+b for a,b in ranges):raise SystemExit('Unexpected wide home path segment')
  text=bytes(data[start:end]).decode('utf-16le')
  match=re.search(r'/work/(?:cx-wine(?:-gst)?-stage|ntdll-candidate-stage)(/.*)$',text)
  if not match:raise SystemExit('Unknown wide Wine home path: '+str(file))
  tail=match.group(1);prefix_size=len(text[:match.start(1)].encode('utf-16le'))//2;portable='/opt/opengame';extra=prefix_size-len(portable)
  padding='/.'*(extra//2) if extra%2==0 else '/'+'/.'*((extra-1)//2)
  replacement=(portable+padding+tail).encode('utf-16le')
  if len(replacement)!=end-start:raise SystemExit('Wide replacement changes offsets')
  data[start:end]=replacement;replaced+=1;cursor=end+2
 if re.search(pattern,data) or wide_needle in data:raise SystemExit('Remaining home path: '+str(file))
 file.write_bytes(data)
 after=subprocess.check_output(nm+[str(file)],stderr=subprocess.DEVNULL) if macho else pe_identity(data)
 if before!=after:raise SystemExit('Export list changed: '+str(file))
 changes.append({'format':'Mach-O' if macho else 'PE','file':str(file.relative_to(args.runtime)),'normalizedStrings':replaced,'exportsPreserved':True})
if args.report:args.report.write_text(json.dumps(changes,indent=2)+'\n')
print('PASS: sanitized',len(changes),'Wine binaries; external exports preserved; re-sign required')
