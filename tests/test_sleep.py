"""Exercise sleep ownership and saved menu choices against a fake powerd."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT/'extensions/kindleair/kindleair.sh').read_text()
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    base, state, tools = root/'app', root/'state', root/'bin'
    for path in [base, state, tools]: path.mkdir()
    power = root/'power'; events = root/'events'
    power.write_text('0\n'); events.write_text('')
    idle=base/'idle-control.sh'; idle.write_text('#!/bin/sh\n[ "${TEST_IDLE:-0}" = 1 ]\n'); idle.chmod(0o755)
    for name, body in {
        'lipc-get-prop': '[ -z "${DBUS_SYSTEM_BUS_ADDRESS:-}" ] || exit 21\ncat "$TEST_POWER"',
        'lipc-set-prop': '[ -z "${DBUS_SYSTEM_BUS_ADDRESS:-}" ] || exit 21\n[ ! -f "$TEST_FAIL" ] || exit 1\nprintf "%s\\n" "$3" > "$TEST_POWER"\nprintf "%s\\n" "$3" >> "$TEST_EVENTS"',
        'eips': 'exit 0',
    }.items():
        p = tools/name; p.write_text('#!/bin/sh\n'+body+'\n'); p.chmod(0o755)
    adapted = source.replace('BASE=/mnt/us/extensions/kindleair', f'BASE={base}').replace('STATE=/tmp/kindleair-control', f'STATE={state}')
    functions = adapted.split('case "${1:-status}" in', 1)[0]
    env = dict(os.environ, PATH=str(tools)+os.pathsep+os.environ['PATH'],
               DBUS_SYSTEM_BUS_ADDRESS='unix:path=/private-test-bus', TEST_POWER=str(power), TEST_EVENTS=str(events), TEST_FAIL=str(root/'fail'))
    def run(code): subprocess.run(['sh','-c',functions+'\n'+code], env=env, check=True)
    run('keep_awake_enabled; apply_sleep_setting')
    assert power.read_text().strip() == '1' and (state/'sleep-owned').exists()
    # Refresh after firmware/another application clears the property.
    power.write_text('0\n'); run('apply_sleep_setting')
    assert power.read_text().strip() == '1'
    # Turning off releases our own inhibitor and persists across script invocations.
    run('save_sleep_setting 0; apply_sleep_setting')
    assert power.read_text().strip() == '0' and not (state/'sleep-owned').exists()
    assert (base/'keep-awake.conf').read_text().strip() == '0'
    run('! keep_awake_enabled')
    # An inhibitor already held before acquisition is not ours to clear.
    power.write_text('1\n'); (base/'keep-awake.conf').write_text('1\n')
    run('apply_sleep_setting; release_sleep_inhibit')
    assert power.read_text().strip() == '1' and not (state/'sleep-owned').exists()
    # Failed acquisition must not record ownership.
    power.write_text('0\n'); (root/'fail').touch()
    run('! apply_sleep_setting')
    assert not (state/'sleep-owned').exists()
    (root/'fail').unlink()
    # Test the actual menu entry points while stopped: save choice without forcing wake.
    script=root/'kindleair.sh'; script.write_text(adapted)
    for action, expected in [('sleep-off','0'),('sleep-on','1')]:
        subprocess.run(['sh',str(script),action],env=env,check=True)
        assert (base/'keep-awake.conf').read_text().strip() == expected
        assert power.read_text().strip() == '0'
    env['TEST_IDLE']='1'
    run('alive() { return 1; }; save_sleep_setting 0; apply_sleep_setting')
    assert power.read_text().strip()=='1' and (state/'sleep-owned').exists()
print('Sleep setting passed: persistence, refresh, ownership, failure and menu actions')
