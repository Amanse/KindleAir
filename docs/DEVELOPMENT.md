# Development

## Repository layout

```text
extensions/kindleair/   KUAL extension and bundled runtime
scripts/               Package, validate and rebuild tools
tests/                 Process lifecycle, input forwarding, sleep setting, low-power restoration, idle timer and KUAL menu regression checks
docs/                  Architecture, troubleshooting and build notes
```

The runtime archive contains only third-party ARM Linux binaries/libraries plus the local account helper. Kindle firmware libraries are loaded on the device and are not redistributed here.

## Validate and package

Use Python 3.12 or later and a POSIX shell:

```sh
python3 scripts/validate.py
python3 scripts/package.py
```

Validation checks shell syntax, JSON/XML metadata, ARM ELF architecture and runtime dependency closure, the helper's SHA-256 hash, process input/output, error, exit and shutdown behavior, plus sleep preference persistence, inhibitor ownership, low-power restoration, idle-timer boundaries, stale telemetry, sleep guards and KUAL menu shape. The menu test re-implements KUAL's `parse.awk` RPN conditions to prove exactly one On/Off row is visible per setting, and checks that every menu action maps to a command implemented by `kindleair.sh`. These checks do not replace an on-device audio test. The working build was separately tested on the Kindle; see the README compatibility table.

## Build the Avahi account helper

With an ARMv7 hard-float musl cross compiler on Linux:

```sh
CC=arm-linux-musleabihf-gcc sh scripts/build-helper.sh
```

The helper deliberately has no compile-time dependency on firmware headers. It overrides only `getpwnam("avahi")` and `getgrnam("avahi")`; other names are delegated with `dlsym(RTLD_NEXT, ...)`. Its struct layout targets 32-bit ARM musl, not arbitrary operating systems.

The checked-in helper was built on macOS using Clang for the object and LLVM LLD for ELF linking. Equivalent commands, with `ld.lld` on PATH, are:

```sh
mkdir -p build
clang -target armv7-unknown-linux-musleabihf \
  -march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=hard \
  -fPIC -ffreestanding -nostdinc -O2 -Wall -Wextra -Werror \
  -c extensions/kindleair/avahi-accounts.c -o build/avahi-accounts.o
ld.lld -m armelf_linux_eabi -shared --hash-style=both \
  -soname kindleair-avahi-accounts.so \
  -o build/kindleair-avahi-accounts.so build/avahi-accounts.o
```

Rust's bundled `rust-lld` can also be invoked with `-flavor gnu` before the same linker flags. Compiler/linker versions can change the binary hash; record the hash of your own build.

## Reassemble the runtime

```sh
python3 scripts/build_runtime.py \
  --helper build/kindleair-avahi-accounts.so
```

The script downloads the exact APK versions in `packages.json`, verifies their SHA-256 hashes, extracts only the required runtime paths, and adds the locally built helper. APK contents and links are filtered during extraction. It writes `build/runtime.tar.gz` and `build/local-build.json`.

To use the result:

```sh
cp build/runtime.tar.gz build/local-build.json extensions/kindleair/
python3 scripts/validate.py
python3 scripts/package.py
```

For an offline rebuild, prepopulate a cache with the exact APK files and pass `--cache /path/to/apks`. The manifest records the original `latest-stable` mirror URLs. Alpine can rotate old packages when that alias advances; if necessary, locate the exact files in the corresponding historical Alpine branch or an existing cache, and keep the recorded hashes. Do not silently substitute dependency versions.

This rebuild assembles upstream binary packages; it does not compile Shairport or every dependency from source. `packages.json` links the immutable Alpine source recipes for their corresponding sources, patches and build options. Rebuilding those packages from source uses Alpine's `abuild` workflow. The local helper source is included directly.

## Device debugging

Normal use needs no SSH. During development, KOReader's SSH server allows testing and deployment without repeated USB transfers. Use a dedicated key; never commit it. Copy updates to a temporary path and rename them into place rather than truncating a supervisor script while it is running.

On the tested device, `/bin/gdb` was available. Running the receiver under it located the original null-string metadata crash. The bundled receiver's stdout is raw PCM, so redirect it to a suitable sink or `/dev/null` while debugging and keep diagnostics on stderr.

Keep a matching LuaJIT/firmware GStreamer ABI. Do not export the bundled musl library search path into the native mixer process.
