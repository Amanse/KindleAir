# KindleAir

Turn a jailbroken Kindle into a **classic AirPlay → Bluetooth audio bridge**.

```text
Mac / iPhone / iPad ──AirPlay over Wi-Fi──> Kindle ──Bluetooth──> headphones / speaker
```

KindleAir combines [Shairport Sync](https://github.com/mikebrady/shairport-sync) with the Kindle's native GStreamer `mixersink` audio output, following [KinAMP](https://github.com/kbarni/KinAMP)'s audio pipeline and Bluetooth pairing dialog.

**Status: Beta**, version **0.2.0-beta.3**. KindleAir should work on jailbroken Kindles with Bluetooth audio support, KUAL and KOReader, where the firmware provides the compatible native audio mixer. Playback is confirmed on a Kindle Basic 3 (10th generation); other models and firmware versions have not yet been verified.

[Download the current beta](https://github.com/Amanse/KindleAir/releases/tag/v0.2.0-beta.3).

## Requirements

- A jailbroken Kindle with Bluetooth audio hardware.
- **KUAL** and **KOReader** installed at their usual locations. KindleAir uses KOReader's existing LuaJIT.
- A Bluetooth speaker or headphones and an AirPlay sender on the same Wi-Fi network as the Kindle.
- Approximately 6 MB of USB storage plus about 12 MB of temporary runtime space.

| Tested component | Version / result |
| --- | --- |
| Kindle | Basic 3, 10th generation |
| Firmware | 5.18.1.1.1 |
| Kernel / CPU | Linux 4.1.15, ARMv7 Cortex-A9 |
| Firmware audio | GStreamer 0.10, `mixersink` |
| AirPlay receiver | Shairport Sync 5.5.1, classic AirPlay |
| Bluetooth endpoints | JBL Live 770NC; JBL Clip 4 (low-power beta) |
| Confirmed | Discovery, RTSP connection, audible output, sleep controls, low-power playback and CPU/frontlight restoration, resync and idle sleep |

## Install

1. Clone or download this repository.
2. Connect the Kindle by USB.
3. Copy **`extensions/kindleair`** into the Kindle's **`extensions`** directory. The resulting path on the Kindle must be `/mnt/us/extensions/kindleair/`.
4. Safely eject the Kindle and unplug USB.

The repository includes the working ARM runtime in `extensions/kindleair/runtime.tar.gz`; compiling is not required for installation. No firmware flashing, system-library replacement or root filesystem remount is needed.

To make a drag-and-drop installation ZIP from a checkout:

```sh
python3 scripts/package.py
```

Extract the resulting `dist/KindleAir-0.2.0-beta.3.zip` onto the Kindle's USB storage root.

## Pair and play

1. Put your Bluetooth headphones or speaker into pairing mode.
2. Open **KUAL → KindleAir → Pair Bluetooth speaker** and select it.
3. Choose **Start AirPlay receiver** and wait about 10 seconds.
4. Select **KindleAir** in your Mac, iPhone or iPad's AirPlay audio output menu and play music.
5. Use **Stop AirPlay receiver** before reconnecting USB storage.

The pairing action opens the firmware Bluetooth dialog used by KinAMP. It avoids VoiceView's setup flow and can be useful when the normal Bluetooth settings menu is hidden.

KUAL also provides **Status** and **Collect diagnostics**. KindleAir starts on demand; it does not install a boot service. SSH is optional and only needed for development or debugging.

## Optional low-power AirPlay mode

**Saved option:** open **KUAL → KindleAir → Settings → Low power mode → Enable / Disable**. It defaults to **disabled**, persists across sessions, and applies immediately to a running receiver. The regular Start action uses this choice. **Show setting** displays it.

For a one-session override, choose **KUAL → KindleAir → Start AirPlay (low power)**. You can select it while the receiver is already running; the stream does not need to restart.

Low-power mode:

- Uses the adaptive `ondemand` CPU governor when supported, instead of a fixed `performance` governor. The CPU can still boost when audio needs it; no frequency cap is imposed.
- Turns off the frontlight on entry.
- Quiets receiver diagnostics and checks component health every 10 seconds instead of every 2 seconds.
- Keeps Wi-Fi, Bluetooth, the firmware interface and KUAL available.

Choose **Restore normal power** to leave the receiver running with the original CPU/light settings. **Stop AirPlay receiver** also restores them. Manual governor or brightness changes made after entering the mode take precedence during restoration. The quick-start and Restore normal power actions affect only the current session; they do not change the saved Settings choice. The device preference is stored in `low-power.conf` and is not included in release ZIPs.

This reduces avoidable activity but does not put the Kindle into deep sleep: AirPlay needs Wi-Fi, decoding and Bluetooth transmission to remain active. Battery-life improvement has not been quantified in a controlled test. Unsupported hardware controls are skipped, so behavior can differ across Kindle models.

## Resync audio and accumulated delay

Choose **KUAL → KindleAir → Resync audio / clear delay**. This briefly resets the firmware mixer and drains queued PCM without restarting the AirPlay receiver. Playback should resume automatically on the same connection.

The raw PCM queue is capped at 16 KiB / four buffers (about 93 ms at 44.1 kHz stereo), dropping old queued data if downstream playback falls behind. The previous time-only limit could not reliably bound buffers without timestamps. This addresses accumulated local backlog; it does not remove AirPlay's negotiated delay or measure the Bluetooth speaker's internal queue.

A resync can make audio slightly ahead of Apple Music lyrics after removing delay. Exact lyric/video alignment is not guaranteed, and KindleAir cannot change the sender's lyric display clock. The on-device resync test preserved the receiver process and user-confirmed playback recovered.

## Idle sleep timer

Open **KUAL → KindleAir → Settings → Idle sleep timer**. Choose **Off**, **1, 5, 10, 15, 30, 60 or 120 minutes**, or **Show setting**. The saved default is **Off**. Changes apply to the running receiver and start a fresh idle countdown.

Idle means no new PCM audio, not merely no connected sender. Audio progress resets the countdown, including silent audio data that is still being streamed. Paused or disconnected senders count as idle when they stop delivering audio. Stale or unavailable progress telemetry is treated as unknown and will not trigger sleep.

An enabled timer keeps the Kindle awake until the selected idle interval expires, even if ordinary keep-awake is disabled. At expiry KindleAir stops the receiver, restores CPU/frontlight settings, removes its firewall rules, releases its own sleep inhibitor, and requests firmware sleep. It does not override another application's sleep inhibitor or toggle an already-inactive Kindle awake. Wake the Kindle and start KindleAir again for another session.

Custom whole-minute values from 0 (Off) through 1440 can be set over SSH with `sh /mnt/us/extensions/kindleair/kindleair.sh idle-minutes N`. The device preference `idle-timer.conf` is excluded from installation ZIPs.

## Sleep behavior

Open **KUAL → KindleAir → Sleep behavior**:

- **Keep awake while running** prevents automatic sleep during receiver operation.
- **Allow normal sleep** releases KindleAir's sleep inhibitor and permits the normal firmware timeout.
- **Show sleep setting** displays the saved choice.

The default is Keep awake. Changes are saved for future sessions and apply immediately to a running receiver. While enabled, KindleAir checks the inhibitor every 30 seconds and reapplies it if cleared. An enabled idle timer keeps the device awake until its idle deadline and then stops the receiver and requests sleep. Stop restores normal sleep when KindleAir acquired the inhibitor; it does not clear one already held by another application. Keeping the device awake uses more battery. The preference is stored locally as `extensions/kindleair/keep-awake.conf` and is excluded from release packages.

## Limitations

- Classic AirPlay / RAOP audio only. No AirPlay 2, HomeKit or screen mirroring.
- Bluetooth adds latency. Video lip sync and synchronized multiroom playback are not validated.
- Long unattended operation, idle Bluetooth retention and battery consumption have not been measured.
- The receiver accepts connections without an AirPlay password from reachable devices on the local Wi-Fi network.
- This beta runs its bundled services with the invoking KUAL user's privileges, normally root.
- Stop the receiver before USB file-transfer mode. Wi-Fi client isolation can prevent discovery or playback.

## What it changes

Persistent application files stay under `extensions/kindleair/`. While running, KindleAir extracts a private runtime under `/tmp`, starts private D-Bus and Avahi processes, and creates a `KINDLEAIR` firewall chain for incoming Wi-Fi TCP 5000, UDP 6001–6010 and UDP 5353. Stop removes that chain and the temporary runtime. The saved Sleep behavior setting controls whether KindleAir requests the firmware sleep inhibitor; it releases inhibitors it acquired on Stop.

To uninstall, Stop KindleAir and delete `extensions/kindleair/` over USB. Existing KUAL, KOReader and books remain in place.

## Documentation

- [Architecture and implementation](docs/ARCHITECTURE.md)
- [Troubleshooting and SSH debugging](docs/TROUBLESHOOTING.md)
- [Build, package and validation instructions](docs/DEVELOPMENT.md)
- [Changes and device test results](CHANGELOG.md)
- [Third-party components and source locations](THIRD_PARTY.md)

## Credits and license

[Shairport Sync](https://github.com/mikebrady/shairport-sync) provides the AirPlay receiver. [KinAMP](https://github.com/kbarni/KinAMP) provided the Kindle PCM pipeline and Bluetooth dialog references. Binary dependencies come from official [Alpine Linux](https://alpinelinux.org/) ARMv7 packages.

KindleAir's glue code is [MIT licensed](LICENSE). Bundled dependencies retain their upstream licenses. Their versions, checksums and corresponding source recipe links are recorded in [packages.json](extensions/kindleair/packages.json). KindleAir is an independent project and is not affiliated with Amazon or Apple.
