# Architecture

```mermaid
flowchart LR
    A[AirPlay sender] -->|RAOP / RTSP + RTP| B[Shairport Sync]
    B -->|S16_LE / 44100 Hz / stereo| C[Temporary PCM FIFO]
    C --> D[KOReader LuaJIT audio helper]
    D --> E[Firmware GStreamer filesrc + mixersink]
    E --> F[Amazon audio and Bluetooth services]
    F --> G[Paired headphones or speaker]
    H[Private Avahi + D-Bus] -->|mDNS / _raop._tcp| A
```

## Runtime separation

The receiver and discovery tools are ARMv7 musl binaries from Alpine Linux. `alpine.sh` invokes the bundled musl loader with an explicit library search path. These libraries are not installed into the Kindle's system directories.

The audio helper is different: `sink.sh` launches KOReader's LuaJIT, and `sink.lua` loads the **firmware's** GStreamer library. It probes GStreamer 0.10 first, then 1.0, and uses the matching raw audio caps. Only 0.10 has been tested on the target Kindle. This separation keeps the bundled musl libraries out of the firmware mixer process.

`filesrc` opens the temporary PCM FIFO directly. This follows KinAMP's pipeline and avoids depending on standard input surviving asynchronous shell wrappers.

## Lifecycle

`kindleair.sh start` detaches a supervisor. It checks the mixer pipeline, extracts the runtime, adds scoped Wi-Fi firewall rules, then starts private D-Bus, Avahi, the audio helper and the receiver. A readiness file means the expected processes are alive, not proof of audible output.

`component.sh` records each child's stderr and exit status and propagates termination to the child. It preserves stdin through a separate descriptor for commands that need it. The supervisor notices component exits, gathers recent logs, and shuts down its remaining children. Stop also removes the temporary runtime and firewall chain.

Avahi's standard `/var/run/avahi-daemon` runtime directory is the exception to the unique runtime path. Startup refuses to take over an existing Avahi PID file. No boot-time service is installed.

## Compatibility fixes discovered on the target

### Avahi account lookup

Even with `--no-drop-root`, the packaged Avahi looks up its build-time `avahi` user and group while preparing its runtime directory. Those accounts do not exist on the Kindle.

`avahi-accounts.c` supplies just those lookups with the invoking process's UID/GID and delegates other names to libc. `alpine.sh` preloads the helper **only into bundled Avahi**. No account files are edited. This is a compatibility adaptation, not privilege separation.

### Shairport metadata crash

In the packaged Shairport Sync 5.5.1, disabling metadata leaves its default metadata pipe name unset, while the compiled metadata pipe initializer still calls `strlen` on it. The on-device debugger confirmed a null-string crash at startup. The launcher passes an explicit `--metadata-pipename` under its temporary runtime directory, keeping metadata disabled while avoiding that crash.

### Kindle firewall

The target firmware drops unsolicited incoming Wi-Fi connections. KindleAir adds a dedicated chain for TCP 5000, UDP 6001–6010 and UDP 5353, reached only from `wlan0`. It removes its own rules on normal Stop/exit and leaves the rest of the firewall intact.

### Audio input

An early process wrapper caused the background audio helper to receive `/dev/null` on stdin. The working implementation opens the FIFO directly with GStreamer `filesrc`; the wrapper also now explicitly preserves inherited input through descriptor 3. A pipe-forwarding regression check was run on the Kindle's own shell.

## Bluetooth pairing

The pairing action asks `com.lab126.btfd` to enable Bluetooth and opens the firmware `bt_wizard_dialog` through `com.lab126.pillow`. KinAMP uses the same dialog. KindleAir does not replace the Bluetooth stack or implement its own pairing protocol.
