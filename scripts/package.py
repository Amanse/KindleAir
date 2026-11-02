#!/usr/bin/env python3
"""Create the USB-root installation ZIP; no device logs or credentials."""
from pathlib import Path
import sys
import zipfile
import xml.etree.ElementTree as ET
ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'extensions/kindleair'
version = ET.parse(BASE / 'config.xml').findtext('./information/version')
output = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'dist' / f'KindleAir-{version}.zip'
output.parent.mkdir(parents=True, exist_ok=True)
# Deliberate allowlist: only release files, never a copied device log or key.
files = ['README.md', 'LICENSE', 'alpine.sh', 'avahi-accounts.c', 'component.sh',
         'config.xml', 'kindleair.sh', 'local-build.json', 'menu.json', 'packages.json',
         'runtime.tar.gz', 'power-mode.sh', 'idle-control.sh', 'shairport-sync.conf', 'sink.lua', 'sink.sh']
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    archive.write(ROOT / 'README.md', 'README.md')
    for name in ['LICENSE', 'CHANGELOG.md', 'THIRD_PARTY.md']:
        archive.write(ROOT / name, name)
    for path in sorted((ROOT / 'docs').glob('*.md')):
        archive.write(path, path.relative_to(ROOT))
    for name in files:
        archive.write(BASE / name, f'extensions/kindleair/{name}')
    for path in sorted((BASE / 'licenses').rglob('*')):
        if path.is_file():
            archive.write(path, path.relative_to(ROOT))
print(output)
