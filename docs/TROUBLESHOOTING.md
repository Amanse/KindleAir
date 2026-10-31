# Troubleshooting

## Bluetooth menu is missing

Use KUAL → KindleAir → **Pair Bluetooth speaker**. This opens the firmware's pairing dialog directly, following KinAMP. Put the speaker in pairing mode and disconnect another device if it keeps reconnecting to it. The normal Kindle Bluetooth menu can vary with account, region and firmware settings; its absence alone does not establish a jailbreak problem.

VoiceView has its own confirmation flow. KindleAir does not require VoiceView to remain enabled.

## KindleAir is not listed in AirPlay

- Check KUAL → KindleAir → Status after waiting about 10 seconds.
- Keep both devices on the same Wi-Fi network and disable access-point client isolation if enabled.
- Stop KindleAir before USB file-transfer mode, then eject USB and start it again.
- Inspect `avahi.log`, `dbus.log` and `receiver.log` for the actual startup error.

An existing Avahi PID file causes a deliberate startup refusal. Do not delete another service's PID file or stop it blindly.

## Receiver is listed but silent

Check that the Bluetooth device is connected, the sender is playing, and the sender's AirPlay volume is audible. The working setup sends S16_LE, 44.1 kHz stereo PCM into the firmware mixer. Inspect `sink.log` for its pipeline and state result, and `receiver.log` for an incoming session.

A process reported as running does not prove it is receiving samples or producing audible output. The original background-stdin bug was resolved by using a direct FIFO `filesrc` pipeline; use the current build.

## Startup failure or exit code

Choose **Collect diagnostics**, then inspect these files under `extensions/kindleair/`:

| File | Contents |
| --- | --- |
| `kindleair.log` | Supervisor startup and failure summary |
| `receiver.log` | AirPlay receiver stderr |
| `sink.log` | Firmware mixer helper stderr |
| `avahi.log` | Discovery daemon stderr |
| `dbus.log` | Private bus stderr |
| `*.exit` | Exit status of a component that exited |
| `diagnostics.txt` | Firmware/ABI probe, selected audio state and recent logs |

Exit 139 commonly indicates SIGSEGV. The initial receiver crash was traced with the Kindle's installed GDB to a null metadata pipe name; the current launcher supplies that path explicitly. An `avahi` user lookup failure means the bundled account helper was not loaded correctly.

Diagnostics and receiver logs can contain local addresses, Bluetooth device names and playback metadata. Review and redact them before posting a public issue. Do not post private SSH keys, account credentials or full unreviewed device dumps.

## Optional SSH debugging

KOReader includes an SSH server on many installations. With public-key authentication configured, enable it from KOReader's Network / SSH server menu. The usual port is 2222; use the address and port displayed by your device.

```sh
ssh -p 2222 root@KINDLE_IP
sh /mnt/us/extensions/kindleair/kindleair.sh status
tail -n 80 /mnt/us/extensions/kindleair/receiver.log
```

No SSH key or credentials are included in this repository. SSH is not needed for everyday playback. The SSH server can be stopped independently of KindleAir.

## Remove or recover

Normal shutdown is KUAL → KindleAir → Stop AirPlay receiver. It terminates its children, removes its firewall chain and deletes its extracted runtime. If a crash or forced termination leaves stale state, collect the logs first; a device reboot clears temporary runtime and in-memory firewall state. This prototype does not install a boot service.

## Low-power audio or restoration

If a model stutters in low-power mode, choose **Restore normal power** and compare playback. Adaptive CPU scaling can differ across firmware and hardware. Wi-Fi and Bluetooth remain enabled in either mode. Stop restores hardware settings changed by the mode. If the process was forcibly killed, try Restore normal power before deleting temporary state; a reboot also resets temporary kernel governor state. Battery gains depend on the starting brightness, CPU governor and streaming workload.
