"""Exercise hardware snapshots and restoration without accessing real sysfs."""
from pathlib import Path
import os
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
source=(ROOT/'extensions/kindleair/power-mode.sh').read_text()
with tempfile.TemporaryDirectory() as temporary:
    root=Path(temporary); state=root/'state'; cpu=root/'cpu'; tools=root/'bin'
    for p in [state,cpu,tools]:p.mkdir()
    governor=cpu/'scaling_governor'; available=cpu/'scaling_available_governors'; light=root/'light'
    available.write_text('performance ondemand powersave conservative\n')
    for name,body in {
        'lipc-get-prop':'[ -z "${DBUS_SYSTEM_BUS_ADDRESS:-}" ] || exit 9\ncat "$TEST_LIGHT"',
        'lipc-set-prop':'[ -z "${DBUS_SYSTEM_BUS_ADDRESS:-}" ] || exit 9\nprintf "%s\\n" "$3" > "$TEST_LIGHT"',
    }.items():
        p=tools/name;p.write_text('#!/bin/sh\n'+body+'\n');p.chmod(0o755)
    script=root/'power-mode.sh';script.write_text(source.replace('STATE=/tmp/kindleair-control',f'STATE={state}').replace('CPU=/sys/devices/system/cpu/cpu0/cpufreq',f'CPU={cpu}'))
    env=dict(os.environ,PATH=str(tools)+os.pathsep+os.environ['PATH'],TEST_LIGHT=str(light),DBUS_SYSTEM_BUS_ADDRESS='unix:path=/private-bus')
    def run(action):subprocess.run(['sh',str(script),action],env=env,check=True)
    governor.write_text('performance\n');light.write_text('8\n')
    run('enter')
    assert governor.read_text().strip()=='ondemand' and light.read_text().strip()=='0'
    assert (state/'power-governor').read_text().strip()=='performance'
    # Entering twice must not overwrite the original hardware snapshots.
    run('enter');run('restore')
    assert governor.read_text().strip()=='performance' and light.read_text().strip()=='8'
    assert not list(state.iterdir())
    # User changes during a low-power session take precedence on exit.
    run('enter');governor.write_text('conservative\n');light.write_text('3\n');run('restore')
    assert governor.read_text().strip()=='conservative' and light.read_text().strip()=='3'
    # Do not raise an already power-saving governor; frontlight still turns off.
    governor.write_text('powersave\n');light.write_text('2\n');run('enter')
    assert governor.read_text().strip()=='powersave' and light.read_text().strip()=='0'
    run('restore');assert light.read_text().strip()=='2'
    # No governor support: keep audio alive and still dim the frontlight.
    governor.unlink();available.unlink();run('enter');run('restore')
    assert light.read_text().strip()=='2' and not list(state.iterdir())
print('Low-power snapshots, idempotence, native bus, manual overrides and unsupported CPU passed')
