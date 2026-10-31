import pathlib,subprocess,tempfile,os,signal,time,sys
with tempfile.TemporaryDirectory() as tmp:
 root=pathlib.Path(tmp).resolve()
 source=(pathlib.Path(__file__).resolve().parents[1] / 'extensions/kindleair/component.sh').read_text()
 wrapper=root/'component.sh';wrapper.write_text(source.replace('BASE=/mnt/us/extensions/kindleair','BASE='+str(root)))
 result=subprocess.run(['sh',str(wrapper),'receiver',sys.executable,'-c','import sys;sys.stdout.write("PCM");sys.stderr.write("test failure\\n");sys.exit(7)'],capture_output=True)
 assert result.returncode==7 and result.stdout==b'PCM',result
 assert (root/'receiver.exit').read_text().strip()=='7'
 assert (root/'receiver.log').read_text()=='test failure\n'
 result=subprocess.run(['sh',str(wrapper),'sink',sys.executable,'-c','import sys;sys.stdout.buffer.write(sys.stdin.buffer.read())'],input=b'PCM input test',capture_output=True)
 assert result.returncode==0 and result.stdout==b'PCM input test',result
 pidfile=root/'child.pid'
 proc=subprocess.Popen(['sh',str(wrapper),'sink',sys.executable,'-c',f'import os,time,pathlib;pathlib.Path({str(pidfile)!r}).write_text(str(os.getpid()));time.sleep(60)'])
 for _ in range(100):
  if pidfile.exists():break
  time.sleep(.02)
 assert pidfile.exists()
 child=int(pidfile.read_text());proc.terminate();proc.wait(timeout=3)
 try:os.kill(child,0)
 except ProcessLookupError:pass
 else:raise AssertionError('child still alive after Stop')
print('Component lifecycle passed: PCM stdout, error log, exit status, and child shutdown')
