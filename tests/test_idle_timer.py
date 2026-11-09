"""Idle expiry depends on fresh audio telemetry and monotonic time, never just a connection."""
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
source=(ROOT/'extensions/kindleair/idle-control.sh').read_text()
with tempfile.TemporaryDirectory() as directory:
    root=Path(directory);base=root/'app';state=root/'state';base.mkdir();state.mkdir()
    uptime=root/'uptime';uptime.write_text('100.0 0.0\n')
    script=root/'idle-control.sh';script.write_text(source.replace('BASE=/mnt/us/extensions/kindleair',f'BASE={base}').replace('STATE=/tmp/kindleair-control',f'STATE={state}').replace('UPTIME=/proc/uptime',f'UPTIME={uptime}'))
    def run(*args,expected=0):
        r=subprocess.run(['sh',str(script),*map(str,args)],capture_output=True,text=True)
        assert r.returncode==expected,(args,r.returncode,r.stderr)
        return r.stdout.strip()
    def media(now,last,observed=None):
        uptime.write_text(f'{now}.0 0.0\n');(state/'media-state').write_text(f'{now if observed is None else observed} {last} 4000\n')
    assert run('status')=='0';run('check')
    run('set','1');assert run('status')=='1'
    # Playback continues: source byte progress refreshes last-audio time.
    media(200,199);run('check');assert int((state/'idle-status').read_text())==59
    media(259,200);run('check')
    media(260,200);run('check',expected=10)
    # A stale observation or missing heartbeat is unknown, not idle.
    media(400,200,observed=300);run('check')
    (state/'media-state').unlink();run('check')
    # Changing the timer while already idle starts a fresh interval.
    uptime.write_text('500.0 0.0\n');run('set','1')
    media(550,200);run('check');media(560,200);run('check',expected=10)
    # Invalid values leave the existing setting untouched.
    for bad in ['-1','1.5','oops','1441']:
        run('set',bad,expected=2);assert run('status')=='1'
    run('set','0005');assert run('status')=='5'
    run('set','0');media(9000,1);run('check');assert run('enabled',expected=1)==''
print('Idle timer: defaults, active playback, idle boundary, stale telemetry, reset and validation passed')

controller=(ROOT/'extensions/kindleair/kindleair.sh').read_text().split('case "${1:-status}" in',1)[0]
for inhibit,power_state,should_sleep in [('0','active',True),('1','active',False),('0','screenSaver',False)]:
    with tempfile.TemporaryDirectory() as directory:
        output=Path(directory)/'sleep-request'
        stubs=f"""
native_lipc_get() {{ if [ \"$2\" = state ]; then echo {power_state}; else echo {inhibit}; fi; }}
native_lipc_set() {{ printf '%s' \"$*\" > {output}; }}
request_idle_sleep
""".replace('\"','"')
        subprocess.run(['sh','-c',controller+stubs],check=True,capture_output=True)
        assert output.exists()==should_sleep
        if should_sleep:assert output.read_text()=='com.lab126.powerd powerButton 1'
print('Idle sleep respects external inhibitors and never wakes an inactive Kindle')

# The KUAL toggle turns the timer off and back on at the last chosen delay.
source=(ROOT/'extensions/kindleair/kindleair.sh').read_text()
with tempfile.TemporaryDirectory() as directory:
    root=Path(directory);base=root/'app';state=root/'state';base.mkdir();state.mkdir()
    uptime=root/'uptime';uptime.write_text('100.0 0.0\n')
    helper=(ROOT/'extensions/kindleair/idle-control.sh').read_text()
    helper=helper.replace('BASE=/mnt/us/extensions/kindleair',f'BASE={base}').replace('STATE=/tmp/kindleair-control',f'STATE={state}').replace('UPTIME=/proc/uptime',f'UPTIME={uptime}')
    (base/'idle-control.sh').write_text(helper);(base/'idle-control.sh').chmod(0o755)
    prefix,branches=source.replace('BASE=/mnt/us/extensions/kindleair',f'BASE={base}').replace('STATE=/tmp/kindleair-control',f'STATE={state}').split('case "${1:-status}" in',1)
    script=root/'kindleair.sh'
    script.write_text(prefix+'\nalive() { return 1; }\neips() { :; }\ncase "${1:-status}" in'+branches)
    def run(*args):subprocess.run(['sh',str(script),*map(str,args)],check=True,capture_output=True)
    def status():return subprocess.run(['sh',str(base/'idle-control.sh'),'status'],capture_output=True,text=True,check=True).stdout.strip()
    def last():return subprocess.run(['sh',str(base/'idle-control.sh'),'last'],capture_output=True,text=True,check=True).stdout.strip()
    run('idle-minutes','30');assert status()=='30' and last()=='30'
    run('idle-toggle');assert status()=='0' and last()=='30'
    run('idle-toggle');assert status()=='30' and last()=='30'
    assert last()=='30'  # Off keeps the remembered delay
    run('idle-minutes','0');assert status()=='0' and last()=='30'
    assert last()=='30'
    (base/'idle-last.conf').write_text('bogus\n');assert last()=='15'
print('Idle toggle: off/on at the remembered delay and safe defaults passed')
