# KindleAir 0.1.3

Classic AirPlay audio receiver → Kindle firmware mixer → paired Bluetooth headphones or speaker.

## Verified on this Kindle

Kindle Basic 3 (10th generation), firmware 5.18.1.1.1, Linux 4.1.15. Shairport Sync 5.5.1 runs from a bundled ARMv7 musl runtime. Audio uses the same signed 16-bit stereo, 44.1 kHz PCM / firmware GStreamer 0.10 mixersink approach as KinAMP.

Local AirPlay discovery, RTSP connections, incoming music and audible Bluetooth output to JBL Live 770NC headphones were confirmed on 2026-10-31. Stop/restart and removal of KindleAir's firewall chain were also checked.

## Use

1. Safely eject USB storage and unplug the cable.
2. Keep the Kindle and sender on the same Wi-Fi network.
3. Open KUAL → KindleAir → Pair Bluetooth speaker and connect your headphones/speaker. This uses KinAMP's firmware pairing dialog and bypasses VoiceView setup.
4. Choose Start AirPlay receiver and wait about 10 seconds.
5. Select KindleAir in the sender's AirPlay menu and play audio.
6. Use Stop AirPlay receiver before reconnecting USB storage.

It starts on demand, not at boot. This is classic AirPlay audio; AirPlay 2, HomeKit and screen mirroring are not included. Bluetooth adds delay, so video lip sync and multiroom synchronization are not guaranteed.

## Installation and removal

The persistent installation lives entirely in `extensions/kindleair/`. Existing KUAL and KOReader are required; KOReader's LuaJIT runs the firmware audio helper. The bundled runtime is extracted into a unique temporary directory while running. KindleAir uses a private D-Bus and Avahi process and temporarily opens Wi-Fi TCP 5000, UDP 6001–6010 and UDP 5353 through its own `KINDLEAIR` firewall chain. Stop removes those rules and the temporary runtime.

No firmware flashing or system-library replacement is involved. The bundled Avahi uses a small local account-lookup helper so it can run without adding an `avahi` account to the Kindle. Shairport receives an explicit temporary metadata-pipe path to avoid a null-string startup crash in this package. The audio helper opens the PCM FIFO directly using `filesrc`, matching KinAMP.

While running, KindleAir requests the firmware's sleep inhibitor when initially clear and releases its request on Stop. Long unattended operation and idle Bluetooth retention have not yet been tested.

To remove: Stop KindleAir, connect USB, then delete `extensions/kindleair/`.

## Diagnostics

KUAL → KindleAir → Collect diagnostics saves `diagnostics.txt` in its installation folder. The files `kindleair.log`, `receiver.log`, `sink.log`, `avahi.log` and `dbus.log` identify startup or stream failures. Component exit statuses are recorded as `*.exit`. Runtime logging is reduced from debug verbosity for normal use.

An optional KOReader SSH server was used for debugging, with a dedicated public key in `koreader/settings/SSH/authorized_keys`. The SSH key is not included in this archive. The server is independent of KindleAir and can be stopped from KOReader when troubleshooting is finished.

## Sources and licensing

- Shairport Sync: https://github.com/mikebrady/shairport-sync (package version 5.5.1).
- Kindle audio and Bluetooth dialog reference: https://github.com/kbarni/KinAMP.
- Third-party binaries: official Alpine Linux ARMv7 packages.

`packages.json` records exact versions, SHA-256 hashes, upstream licenses and immutable source recipe links. `local-build.json` identifies the MIT-licensed Avahi account helper; its source is included in `avahi-accounts.c`. Other KindleAir glue is MIT licensed. Third-party licenses remain with their respective packages.
