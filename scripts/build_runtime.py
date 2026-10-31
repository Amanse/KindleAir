#!/usr/bin/env python3
"""Reassemble the pinned ARM runtime from checksummed Alpine APKs and a built helper."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'extensions/kindleair'
SELECTED = ['lib', 'usr/lib', 'usr/bin/shairport-sync', 'usr/bin/dbus-daemon', 'usr/bin/dbus-send', 'usr/sbin/avahi-daemon']

def wanted(name):
    return any(name == path or name.startswith(path + '/') for path in SELECTED)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--helper', type=Path, required=True, help='Built ARMv7 musl account helper .so')
    parser.add_argument('--cache', type=Path, default=ROOT / 'build/apk')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/runtime.tar.gz')
    args = parser.parse_args()
    if not args.helper.is_file():
        parser.error('Build the account helper first; see docs/DEVELOPMENT.md')
    args.cache.mkdir(parents=True, exist_ok=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    packages = json.loads((BASE / 'packages.json').read_text())
    with tempfile.TemporaryDirectory() as temporary:
        runtime = Path(temporary)
        for package in packages:
            url = package['url']
            path = args.cache / PurePosixPath(url).name
            if not path.exists():
                with urllib.request.urlopen(url, timeout=60) as response, path.open('wb') as output:
                    shutil.copyfileobj(response, output)
            if hashlib.sha256(path.read_bytes()).hexdigest() != package['sha256']:
                raise SystemExit(f'Checksum mismatch: {path}; remove the cached file and retry')
            # APK v2 contains concatenated gzip/tar streams. Only extract the runtime subset.
            with tarfile.open(path, 'r:gz', ignore_zeros=True) as archive:
                members = [m for m in archive if wanted(m.name)]
                archive.extractall(runtime, members=members, filter='data')
            print(f"Verified {package['name']} {package['version']}")
        helper = runtime / 'usr/lib/kindleair-avahi-accounts.so'
        shutil.copyfile(args.helper, helper)
        helper.chmod(0o755)
        with tarfile.open(args.output, 'w:gz') as archive:
            for name in SELECTED:
                archive.add(runtime / name, arcname=name)
        manifest = json.loads((BASE / 'local-build.json').read_text())
        manifest['sha256'] = hashlib.sha256(helper.read_bytes()).hexdigest()
        (args.output.parent / 'local-build.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(args.output)

if __name__ == '__main__':
    main()
