"""KUAL menu shape: one Settings area, state-aware toggles, and every action
wired to a command that kindleair.sh actually implements.

The ``if`` conditions are evaluated with the same RPN semantics as KUAL's
parse.awk, so a toggle that can never appear (or two that always appear) fails
this check without needing a device.
"""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'extensions/kindleair'
MENU = json.loads((BASE / 'menu.json').read_text())
SOURCE = (BASE / 'kindleair.sh').read_text()
PREF = '/mnt/us/extensions/kindleair'

# parse.awk only forwards these keys; anything else is a menu syntax error.
ALLOWED = {'name', 'action', 'params', 'priority', 'if', 'exitmenu',
           'checked', 'refresh', 'status', 'date', 'hidden', 'items'}
ACTIONS = {'start', 'start-low', 'stop', 'normal-power', 'power-low',
           'power-normal', 'power-status', 'settings-status', 'status',
           'bluetooth', 'sleep-on', 'sleep-off', 'sleep-status', 'resync',
           'idle-toggle', 'idle-minutes', 'idle-status', 'diagnose'}

branches = SOURCE.split('case "${1:-status}" in', 1)[1]
implemented = set()
for line in branches.splitlines():
    match = re.match(r'^ ([a-z-]+(?:\|[a-z-]+)*)\)', line)
    if match:
        implemented.update(match.group(1).split('|'))
assert ACTIONS <= implemented, ACTIONS - implemented


def walk(items):
    for item in items:
        assert set(item) <= ALLOWED, (item['name'], set(item) - ALLOWED)
        assert item['name'].strip(), 'empty label'
        assert len(item['name']) <= 44, ('label too wide', item['name'])
        if 'items' in item:
            assert 'action' not in item, item['name']
            walk(item['items'])
        else:
            assert item.get('action') == './kindleair.sh', item['name']
            command = item.get('params', '').split()[0]
            assert command in ACTIONS, (item['name'], command)


walk(MENU['items'])

top = MENU['items'][0]
assert top['name'] == 'KindleAir'
names = [item['name'] for item in top['items']]
assert names == ['Start AirPlay receiver', 'Stop AirPlay receiver',
                 'Pair Bluetooth speaker', 'Resync audio / clear delay',
                 'Status', 'Collect diagnostics', 'Settings'], names
# Session-only power shortcuts now live in Settings as toggles.
assert not [n for n in names if 'low power' in n.lower() or 'restore' in n.lower()]

settings = top['items'][-1]
assert settings['name'] == 'Settings'
toggle_rows = {item['name']: item for item in settings['items'] if 'if' in item}
assert len(toggle_rows) == 6, list(toggle_rows)
delay = next(item for item in settings['items'] if item['name'] == 'Auto sleep delay')
show = next(item for item in settings['items'] if item['name'] == 'Show current settings')
recover = next(item for item in settings['items'] if item['name'].startswith('Restore'))
assert show['params'] == 'settings-status'
assert recover['params'] == 'normal-power'
assert [item['params'] for item in delay['items']] == [
    'idle-minutes 0', 'idle-minutes 1', 'idle-minutes 5', 'idle-minutes 10',
    'idle-minutes 15', 'idle-minutes 30', 'idle-minutes 60', 'idle-minutes 120']

# Toggle rows refresh in place, keep KUAL open and hide the command echo.
for item in toggle_rows.values():
    assert item.get('refresh') is True, item['name']
    assert item.get('exitmenu') is False, item['name']
    assert item.get('status') is False, item['name']
    assert any(f'"{PREF}/{name}"' in item['if']
               for name in ('low-power.conf', 'keep-awake.conf', 'idle-timer.conf')), item['if']

# --- KUAL parse.awk RPN evaluation -------------------------------------------
OPERATORS = ('-gg!', '-ext', '-gg', '-e', '-f', '-z!', '-m', '-o', '!', '&&', '||')


def tokenize(expression):
    """Split like RPN_tokenize: quoted strings and operators are single tokens."""
    tokens, index = [], 0
    while index < len(expression):
        char = expression[index]
        if char.isspace():
            index += 1
            continue
        if char == '"':
            end = expression.index('"', index + 1)
            tokens.append(expression[index + 1:end])
            index = end + 1
            continue
        operator = next((op for op in OPERATORS
                         if expression.startswith(op, index)
                         and not (op == '-gg' and expression.startswith('-gg!', index))), None)
        if operator:
            tokens.append(operator)
            index += len(operator)
            continue
        end = index
        while end < len(expression) and not expression[end].isspace():
            end += 1
        tokens.append(expression[index:end])
        index = end
    return tokens


def evaluate(expression, files):
    """Mirror RPN_eval_bool for the operators the menu uses."""
    stack = []
    for token in tokenize(expression):
        if token == '!':
            stack.append(not stack.pop())
        elif token in ('-e', '-f'):
            stack.append(stack.pop() in files)
        elif token == '-z!':
            name = stack.pop()
            stack.append(name in files and files[name] == '')
        elif token in ('-gg', '-gg!'):
            pattern, name = stack.pop(), stack.pop()
            content = files.get(name)
            if content is None:
                stack.append(False)  # unreadable file: both -gg and -gg! are false
            else:
                found = re.search(pattern, content.splitlines()[0] if content else '') is not None
                stack.append(found if token == '-gg' else not found)
        elif token in ('-m', '-o'):
            raise AssertionError('model/config comparisons are not used by this menu')
        elif token in ('&&', '||'):
            right, left = stack.pop(), stack.pop()
            stack.append(left and right if token == '&&' else left or right)
        else:
            stack.append(token)
    assert len(stack) == 1, (expression, stack)
    return bool(stack[0])


LOW = f'{PREF}/low-power.conf'
KEEP = f'{PREF}/keep-awake.conf'
IDLE = f'{PREF}/idle-timer.conf'
CASES = [
    # low-power, keep-awake, idle-timer files -> the row that must be visible
    ({}, 'Off', 'On', 'Off'),
    ({LOW: '0\n', KEEP: '1\n', IDLE: '0\n'}, 'Off', 'On', 'Off'),
    ({LOW: '1\n', KEEP: '0\n', IDLE: '15\n'}, 'On', 'Off', 'On'),
    ({LOW: '1\n', KEEP: '1\n', IDLE: '120\n'}, 'On', 'On', 'On'),
    ({LOW: 'garbage\n', KEEP: 'junk\n', IDLE: 'nope\n'}, 'Off', 'Off', 'Off'),
]
for files, low, keep, idle in CASES:
    visible = [name for name, item in toggle_rows.items() if evaluate(item['if'], files)]
    assert len(visible) == 3, (files, visible)
    for prefix in (f'Low power mode: {low}', f'Keep awake: {keep}', f'Auto sleep: {idle}'):
        assert len([name for name in visible if name.startswith(prefix)]) == 1, (files, prefix, visible)

print('Menu: single Settings area, state-aware toggles, delay presets and wired actions passed')
