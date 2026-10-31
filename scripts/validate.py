#!/usr/bin/env python3
"""Validate release metadata, shell syntax, helper provenance and ARM ELF dependencies."""
from pathlib import Path
import hashlib
import json
import struct
import subprocess
import tarfile
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'extensions/kindleair'
for path in BASE.glob('*.sh'):
    subprocess.run(['sh', '-n', str(path)], check=True)
json.loads((BASE / 'menu.json').read_text())
packages = json.loads((BASE / 'packages.json').read_text())
assert len({p['name'] for p in packages}) == len(packages)
for package in packages:
    assert len(package['sha256']) == 64
    assert package['url'].startswith('https://dl-cdn.alpinelinux.org/alpine/')
    assert package['source_recipe'].startswith('https://gitlab.alpinelinux.org/alpine/aports/')
version = ET.parse(BASE / 'config.xml').findtext('./information/version')
assert f'KindleAir {version}' in (BASE / 'kindleair.sh').read_text()

with tempfile.TemporaryDirectory() as directory:
    runtime = Path(directory)
    with tarfile.open(BASE / 'runtime.tar.gz') as archive:
        archive.extractall(runtime, filter='data')
    helper = runtime / 'usr/lib/kindleair-avahi-accounts.so'
    manifest = json.loads((BASE / 'local-build.json').read_text())
    assert hashlib.sha256(helper.read_bytes()).hexdigest() == manifest['sha256']
    seen = set()
    def check(path):
        path = path.resolve()
        assert path.is_relative_to(runtime.resolve()), path
        if path in seen:
            return
        seen.add(path)
        data = path.read_bytes()
        assert data[:7] == b'\x7fELF\x01\x01\x01', path
        assert struct.unpack_from('<H', data, 18)[0] == 40, path  # EM_ARM
        offset = struct.unpack_from('<I', data, 32)[0]
        size, count = struct.unpack_from('<HH', data, 46)
        sections = [struct.unpack_from('<10I', data, offset+i*size) for i in range(count)]
        for section in sections:
            if section[1] != 6:  # SHT_DYNAMIC
                continue
            strings = sections[section[6]]
            table = data[strings[4]:strings[4]+strings[5]]
            for index in range(section[4], section[4]+section[5], 8):
                tag, value = struct.unpack_from('<iI', data, index)
                if tag != 1:  # DT_NEEDED
                    continue
                name = table[value:].split(b'\0', 1)[0].decode()
                target = next((p for p in [runtime/'lib'/name, runtime/'usr/lib'/name] if p.exists()), None)
                assert target is not None, (path, name)
                check(target)
    for name in ['usr/bin/shairport-sync', 'usr/bin/dbus-daemon', 'usr/bin/dbus-send', 'usr/sbin/avahi-daemon', manifest['file']]:
        check(runtime/name)
    print(f'{version}: metadata, shell syntax, helper hash and {len(seen)} ARM ELF files verified')
subprocess.run(['python3', str(ROOT / 'tests/test_component.py')], check=True)

subprocess.run(["python3", str(ROOT / "tests/test_sleep.py")], check=True)
subprocess.run(["python3", str(ROOT / "tests/test_power_mode.py")], check=True)
