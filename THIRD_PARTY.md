# Third-party components

KindleAir is a wrapper and audio bridge around upstream software. It does not contain Amazon firmware libraries or user device/account data.

- **Shairport Sync 5.5.1:** https://github.com/mikebrady/shairport-sync/tree/5.5.1 — AirPlay receiver. Its upstream notices are in `extensions/kindleair/licenses/Shairport-Sync-COPYING`.
- **KinAMP:** https://github.com/kbarni/KinAMP — reference for the raw PCM / firmware GStreamer pipeline and Bluetooth pairing dialog. KinAMP binaries and firmware libraries are not bundled.
- **Alpine Linux ARMv7 packages:** the unmodified receiver, discovery tools and shared-library dependencies are extracted from official Alpine APKs.
- **Local Avahi account helper:** MIT-licensed source in `extensions/kindleair/avahi-accounts.c`; build record in `local-build.json`.

The authoritative inventory is [packages.json](extensions/kindleair/packages.json). Each entry records the exact package version, original download URL, original APK SHA-256 hash, Alpine's declared license expression, and an immutable source-recipe URL. Those recipes identify upstream source archives, patches, checksums and build instructions. Their upstream licenses and notices continue to apply; the repository's MIT license covers KindleAir glue only.

The inventory includes packages whose complete APK was needed for dependency resolution even when only a subset, or no executable, is retained in `runtime.tar.gz`. For example, a shell package dependency does not mean KindleAir replaces the Kindle's system shell. `scripts/build_runtime.py` only extracts `lib/`, `usr/lib/` and the selected service executables and matching D-Bus client.

General license texts are provided in the extension's `licenses/` directory for reference. A license expression marked `custom` requires the upstream notices; it does not mean MIT by default. Source recipe links and third-party license terms should be preserved when redistributing the runtime. Any modified third-party source or binary should be clearly identified separately from the original APK checksums.
