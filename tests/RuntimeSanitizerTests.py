"""Execute a real native fixture after sanitizing; reject unknown home paths."""
from pathlib import Path
import json,os,shutil,subprocess,tempfile
repo=Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='OpenGame-Sanitizer-') as directory:
 root=Path(directory);runtime=root/'Runtime';runtime.mkdir();(runtime/'manifest.json').write_text('{}')
 def fixture(name,value,compiler):
  source=root/(name+'.c');source.write_text('#include <stdio.h>\nconst char *location='+json.dumps(value)+';\nint main(void){puts(location);puts(location+'+str(len(value.encode())-4)+');return 0;}\n')
  binary=runtime/name;subprocess.run(compiler+['-g','-O0',str(source),'-o',str(binary)],check=True);return binary
 native=fixture('native',str(Path.home())+'/OpenGame-test/work/cx-wine-stage/bin',['xcrun','clang'])
 cc=os.environ.get('OG_MINGW_CC') or shutil.which('x86_64-w64-mingw32-gcc')
 if cc:
  pe=fixture('native.exe',str(Path.home())+'/OpenGame-test/work/cx-wine-gst-stage/bin',[cc])
  wide_source=root/'wide.c';wide_value=str(Path.home())+'/OpenGame-test/work/cx-wine-gst-stage/share/wine/mono'
  wide_source.write_text('#include <wchar.h>\nconst wchar_t *location=L'+json.dumps(wide_value)+';\nint main(void){wprintf(L"%ls",location);return 0;}\n')
  wide=runtime/'wide.exe';subprocess.run([cc,'-g','-O0',str(wide_source),'-o',str(wide)],check=True)
 archives=runtime/'Engines/WineFOSS11/lib/wine/x86_64-windows';archives.mkdir(parents=True);archive=archives/'unused.a';archive.write_bytes(b'test-only import archive')
 command=['python3',str(repo/'scripts/sanitize-runtime-paths.py'),str(runtime)]
 subprocess.run(command,check=True)
 assert not archive.exists()
 subprocess.run(['codesign','--force','--sign','-',str(native)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 lines=subprocess.check_output([str(native)],text=True).splitlines()
 assert lines[0].startswith('/opt/opengame/') and lines[0].endswith('/bin')
 assert os.path.normpath(lines[0])=='/opt/opengame/bin'
 assert lines[1]=='/bin','Pointers to shared literal suffixes must stay valid'
 if cc:
  assert (str(Path.home())+'/').encode() not in pe.read_bytes()
  assert (str(Path.home())+'/').encode('utf-16le') not in wide.read_bytes()
 # Idempotence and precise failure: an unrecognized home string is not guessed.
 subprocess.run(command,check=True)
 unknown=fixture('unknown',str(Path.home())+'/private-config',['xcrun','clang'])
 result=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 assert result.returncode!=0 and b'Unknown Wine home path' in result.stderr
 assert (str(Path.home())+'/private-config').encode() in unknown.read_bytes()
print('PASS: native execution, PE code/export identity, portable prefix, import-archive exclusion, idempotence, unknown-path rejection')
