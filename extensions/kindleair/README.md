# KindleAir 0.2.0-beta.4

Classic AirPlay audio receiver → Kindle firmware mixer → paired Bluetooth headphones or speaker.

**Status: Beta.** Should work on jailbroken Kindles with Bluetooth audio support, KUAL and KOReader where a compatible firmware mixer is available. Other models are not yet verified.

## Verified on this Kindle

Kindle Basic 3 (10th generation), firmware 5.18.1.1.1, Linux 4.1.15. Shairport Sync 5.5.1 runs from a bundled ARMv7 musl runtime. Audio uses the same signed 16-bit stereo, 44.1 kHz PCM / firmware GStreamer 0.10 mixersink approach as KinAMP.

Local AirPlay discovery, RTSP connections, incoming music and audible Bluetooth output to JBL Live 770NC headphones were confirmed on 2026-10-31. Stop/restart and removal of KindleAir's firewall chain were also checked. Low-power playback was confirmed with JBL Clip 4; live mode switching, CPU/frontlight restoration and a one-second Stop were checked in the beta. The 0.2.0-beta.4 build was confirmed on the same device for discovery, start/stop cleanup, resync and recovery from a forced supervisor kill.

## Use

1. Safely eject USB storage and unplug the cable.
2. Keep the Kindle and sender on the same Wi-Fi network.
3. Open KUAL → KindleAir → Pair Bluetooth speaker and connect your headphones/speaker. This uses KinAMP's firmware pairing dialog and bypasses VoiceView setup.
4. Choose Start AirPlay receiver and wait about 10 seconds.
5. Select KindleAir in the sender's AirPlay menu and play audio.
6. Use Stop AirPlay receiver before reconnecting USB storage.

It starts on demand, not at boot. This is classic AirPlay audio; AirPlay 2, HomeKit and screen mirroring are not included. Bluetooth adds delay, so video lip sync and multiroom synchronization are not guaranteed.

## Settings

Everything is under **KUAL → KindleAir → Settings**. Each row shows the current state and flips it when tapped:

- **Low power mode: On / Off** — saved default (off initially) that is applied immediately to a running receiver. Uses adaptive CPU scaling when available, turns the frontlight off, quiets receiver logging and reduces supervisor wakeups. Wi-Fi, Bluetooth and KUAL stay available. Stop or turning the setting off restores the saved governor and brightness; later manual brightness/governor changes are respected.
- **Keep awake: On / Off** — default On. Holds the firmware sleep inhibitor while the receiver runs and refreshes it every 30 seconds. Stop releases only an inhibitor KindleAir itself acquired.
- **Auto sleep: On / Off** — idle sleep timer. Turning it on uses the last chosen delay, 15 minutes by default.
- **Auto sleep delay** — Off, 1, 5, 10, 15, 30, 60 or 120 minutes. Idle means no new PCM audio, not merely no connected sender; paused or disconnected senders count as idle. Stale telemetry never triggers sleep.
- **Show current settings** — prints the three settings on screen.
- **Restore normal power (recovery)** — restores CPU/frontlight snapshots left by a forcibly killed session.

An enabled auto-sleep timer keeps the Kindle awake until the selected idle interval expires, even if Keep awake is off. At expiry KindleAir stops the receiver, restores CPU/frontlight settings, removes its firewall rules, releases its own sleep inhibitor and requests firmware sleep. It does not override another application's inhibitor or wake an inactive Kindle.

Changing a setting clears KUAL's parsed-menu cache so the On/Off rows are re-evaluated on the next menu draw. Preferences are `low-power.conf`, `keep-awake.conf`, `idle-timer.conf` and `idle-last.conf`; they are excluded from release packages. Custom whole-minute delays from 0 to 1440 are available over SSH with `sh /mnt/us/extensions/kindleair/kindleair.sh idle-minutes N`.

## Resync audio and accumulated delay

Choose **KUAL → KindleAir → Resync audio / clear delay**. This briefly resets the firmware mixer and drains queued PCM without restarting the AirPlay receiver. Playback should resume automatically on the same connection.

The raw PCM queue is capped at 16 KiB / four buffers (about 93 ms at 44.1 kHz stereo), dropping old queued data if downstream playback falls behind. This addresses accumulated local backlog; it does not remove AirPlay's negotiated delay or measure the Bluetooth speaker's internal queue. A resync can make audio slightly ahead of Apple Music lyrics; exact lyric/video alignment is not guaranteed.

## Crash recovery

Stop restores hardware settings and removes the firewall chain. If the supervisor is killed with `SIGKILL` or the device loses power, the next Start or Stop cleans up first: leftover KindleAir processes (matched by their own executable paths) are stopped, saved CPU/frontlight snapshots restored, and the stale firewall chain and temporary runtime removed. Processes that do not belong to KindleAir are never signalled, and a live Avahi daemon from another application still blocks startup.

## Installation and removal

The persistent installation lives entirely in `extensions/kindleair/`. Existing KUAL and KOReader are required; KOReader's LuaJIT runs the firmware audio helper. The bundled runtime is extracted into a unique temporary directory while running. KindleAir uses a private D-Bus and Avahi process and temporarily opens Wi-Fi TCP 5000, UDP 6001–6010 and UDP 5353 through its own `KINDLEAIR` firewall chain. Stop removes those rules and the temporary runtime.

No firmware flashing or system-library replacement is involved. The bundled Avahi uses a small local account-lookup helper so it can run without adding an `avahi` account to the Kindle. Shairport receives an explicit temporary metadata-pipe path to avoid a null-string startup crash in this package. The audio helper opens the PCM FIFO directly using `filesrc`, matching KinAMP.

To remove: Stop KindleAir, connect USB, then delete `extensions/kindleair/`.

## Diagnostics

KUAL → KindleAir → Collect diagnostics saves `diagnostics.txt` in its installation folder. The files `kindleair.log`, `receiver.log`, `sink.log`, `avahi.log` and `dbus.log` identify startup or stream failures. Component exit statuses are recorded as `*.exit`. Runtime logging is reduced from debug verbosity for normal use.

An optional KOReader SSH server was used for debugging, with a dedicated public key in `koreader/settings/SSH/authorized_keys`. The SSH key is not included in this archive. The server is independent of KindleAir and can be stopped from KOReader when troubleshooting is finished.

## Sources and licensing

- Shairport Sync: https://github.com/mikebrady/shairport-sync (package version 5.5.1).
- Kindle audio and Bluetooth dialog reference: https://github.com/kbarni/KinAMP.
- Third-party binaries: official Alpine Linux ARMv7 packages.

`packages.json` records exact versions, SHA-256 hashes, upstream licenses and immutable source recipe links. `local-build.json` identifies the MIT-licensed Avahi account helper; its source is included in `avahi-accounts.c`. Other KindleAir glue is MIT licensed. Third-party licenses remain with their respective packages.
