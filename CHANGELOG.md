# Changelog

## 0.2.0-beta.3 — 2026-11-02

- Add Resync audio / clear delay without restarting the AirPlay receiver.
- Replace the raw PCM queue's unreliable time-only limit with a bounded, downstream-leaky byte/buffer limit.
- Use an explicitly opened FIFO descriptor and interruptible fdsrc for paused and active mixer resets.
- Add a saved optional idle sleep timer, menu presets, custom CLI minutes and stale-telemetry protection.
- Track actual source byte progress using monotonic time; timer expiry cleans up KindleAir and requests native sleep.
- Integrate the timer with keep-awake settings and respect external sleep inhibitors.
- Confirm on-device resync recovery, continued playback preventing idle expiry, and paused idle expiry stopping the receiver and entering firmware sleep after 61 seconds. Exact sender lyric alignment remains outside receiver control.

## 0.2.0-beta.2 — 2026-10-31

- Add KUAL → KindleAir → Settings → Low power mode with saved Enable/Disable and Show setting actions.
- Default the saved low-power preference to off; regular Start uses the saved choice.
- Apply settings changes to a running receiver without restarting its audio process.
- Keep the quick low-power start as a session override and exclude device preferences from release packages.

## 0.2.0-beta.1 — 2026-10-31

- Introduce optional KUAL low-power AirPlay mode and live restoration to normal power.
- Use adaptive CPU scaling when supported, turn off the frontlight, reduce health polling and quiet receiver diagnostics.
- Restore original CPU/frontlight settings on exit or Stop, respecting later manual changes.
- Keep Wi-Fi, Bluetooth, the firmware interface and KUAL available; do not impose a CPU frequency cap.
- Add hardware snapshot/restoration tests and the matching bundled D-Bus client for live logging control.
- Confirm normal playback on JBL Clip 4 in low-power mode, live mode switching, hardware restoration and responsive Stop on the target Kindle.
- Mark the project Beta and clarify intended compatibility with Bluetooth-capable jailbroken Kindles and the exact tested hardware.

## 0.1.4 — 2026-10-31

- Route native power/Bluetooth LIPC commands to the firmware bus instead of the private discovery bus.
- Add a saved KUAL Sleep behavior setting: Keep awake while running, Allow normal sleep, and Show sleep setting.
- Apply changes immediately to running sessions and refresh an enabled inhibitor every 30 seconds.
- Track inhibitor ownership so Stop releases only one acquired by KindleAir.
- Exclude device preferences from source control and installation ZIPs.

## 0.1.3 — 2026-10-31

Working AirPlay-to-Bluetooth playback confirmed on Kindle Basic 3 / firmware 5.18.1.1.1 with JBL Live 770NC headphones.

- Avoid the packaged Shairport metadata initialization crash by supplying a temporary metadata FIFO path.
- Add scoped incoming Wi-Fi firewall rules and remove them on Stop.
- Open the PCM FIFO directly with firmware GStreamer `filesrc`, following KinAMP.
- Preserve stdin through descriptor 3 in the process wrapper.
- Reduce normal receiver log verbosity and keep display notices within the target screen width.
- Verify local AirPlay discovery, RTSP `200 OK`, incoming music, audible Bluetooth output, and normal Stop/restart cleanup.

## 0.1.2 — diagnostic build

- Add component logs, exit statuses and audio-helper progress messages.
- Request scalar SoXR DSP during compatibility testing.
- Isolate the receiver's exit 139 from the healthy mixer and discovery processes.

## 0.1.1 — discovery and pairing

- Add the private Avahi account-lookup helper, without changing system accounts.
- Add KinAMP's firmware Bluetooth pairing dialog to KUAL.
- Confirm discovery startup and Bluetooth pairing on the device.

## 0.1.0 — initial prototype

- Bundle Shairport Sync 5.5.1 and ARMv7 dependencies.
- Add KUAL lifecycle controls and a firmware GStreamer audio helper.
- Establish separate musl receiver and native firmware audio environments.
