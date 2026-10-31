# Changelog

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
