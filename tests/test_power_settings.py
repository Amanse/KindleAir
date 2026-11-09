"""Saved power choices, immediate live changes and session overrides."""
from pathlib import Path
import json,os,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
source=(ROOT/'extensions/kindleair/kindleair.sh').read_text()
with tempfile.TemporaryDirectory() as directory:
    root=Path(directory);base=root/'app';state=root/'state';base.mkdir();state.mkdir()
    helper=base/'power-mode.sh';helper.write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> "$TEST_EVENTS"\n');helper.chmod(0o755)
    events=root/'events';events.write_text('')
    adapted=source.replace('BASE=/mnt/us/extensions/kindleair',f'BASE={base}').replace('STATE=/tmp/kindleair-control',f'STATE={state}')
    functions=adapted.split('case "${1:-status}" in',1)[0]
    env=dict(os.environ,TEST_EVENTS=str(events))
    def run(code):return subprocess.run(['sh','-c',functions+'\n'+code],env=env,check=True,capture_output=True,text=True).stdout.strip()
    assert run('preferred_power_mode')=='normal'
    run('alive() { return 1; }; save_power_setting 1')
    assert events.read_text()=='' and run('preferred_power_mode')=='low'
    run('alive() { return 0; }; save_power_setting 0')
    assert events.read_text().splitlines()==['restore'] and run('preferred_power_mode')=='normal'
    run('alive() { return 0; }; save_power_setting 1')
    assert events.read_text().splitlines()==['restore','enter'] and run('preferred_power_mode')=='low'
    # Use the actual CLI branches with fake eips/aliveness for a live receiver.
    prefix,branches=adapted.split('case "${1:-status}" in',1)
    script=root/'kindleair.sh';script.write_text(prefix+'\nalive() { return 0; }\neips() { :; }\ncase "${1:-status}" in'+branches)
    for action in ['normal-power','start-low']:
        subprocess.run(['sh',str(script),action],env=env,check=True)
        assert run('preferred_power_mode')=='low' # Session actions do not overwrite saved choice.
    subprocess.run(['sh',str(script),'power-normal'],env=env,check=True)
    assert run('preferred_power_mode')=='normal'
    subprocess.run(['sh',str(script),'power-low'],env=env,check=True)
    assert run('preferred_power_mode')=='low'
menu=json.loads((ROOT/'extensions/kindleair/menu.json').read_text())
settings=next(i for i in menu['items'][0]['items'] if i['name']=='Settings')
assert {'power-low','power-normal'} <= {i['params'] for i in settings['items'] if 'action' in i}
print('Saved power setting: default off, persistence, live changes, CLI/menu and session overrides passed')
