#!/bin/sh
# Session-only low-power controls. Keep the firmware UI, Wi-Fi and Bluetooth alive.
STATE=/tmp/kindleair-control
CPU=/sys/devices/system/cpu/cpu0/cpufreq
light_get() { (unset DBUS_SYSTEM_BUS_ADDRESS; lipc-get-prop com.lab126.powerd flIntensity); }
light_set() { (unset DBUS_SYSTEM_BUS_ADDRESS; lipc-set-prop com.lab126.powerd flIntensity "$1"); }
receiver_log_level() {
 [ -f "$STATE/runtime" ] || return 0
 KA_POWER_RT=$(cat "$STATE/runtime")
 case "$KA_POWER_RT" in /tmp/kindleair.*) ;; *) return 1;; esac
 [ -x "$KA_POWER_RT/usr/bin/dbus-send" ] || return 0
 "$KA_POWER_RT/lib/ld-musl-armhf.so.1" --library-path "$KA_POWER_RT/lib:$KA_POWER_RT/usr/lib" \
  "$KA_POWER_RT/usr/bin/dbus-send" --bus="unix:path=$KA_POWER_RT/bus" --print-reply \
  --dest=org.gnome.ShairportSync /org/gnome/ShairportSync \
  org.freedesktop.DBus.Properties.Set string:org.gnome.ShairportSync.Diagnostics \
  string:Verbosity "variant:int32:$1" >/dev/null
}
restore_power() {
 KA_POWER_RESULT=0
 if [ -f "$STATE/power-governor" ]; then
  KA_OLD_GOVERNOR=$(cat "$STATE/power-governor")
  # Leave a governor explicitly changed by another application alone.
  if [ "$(cat "$CPU/scaling_governor" 2>/dev/null)" = ondemand ]; then
   if ! printf '%s\n' "$KA_OLD_GOVERNOR" > "$CPU/scaling_governor"; then KA_POWER_RESULT=1; fi
  fi
  [ "$KA_POWER_RESULT" = 0 ] && rm -f "$STATE/power-governor"
 fi
 if [ -f "$STATE/power-light" ]; then
  KA_OLD_LIGHT=$(cat "$STATE/power-light")
  KA_CURRENT_LIGHT=$(light_get 2>/dev/null)
  if [ "$KA_CURRENT_LIGHT" = 0 ]; then
   if light_set "$KA_OLD_LIGHT"; then rm -f "$STATE/power-light"; else KA_POWER_RESULT=1; fi
  elif [ -n "$KA_CURRENT_LIGHT" ]; then
   # A manual brightness change takes precedence over the saved value.
   rm -f "$STATE/power-light"
  else KA_POWER_RESULT=1
  fi
 fi
 if [ "${1:-}" != cleanup ]; then receiver_log_level 1 || echo 'Warning: log verbosity restore failed' >&2; fi
 if [ "$KA_POWER_RESULT" = 0 ]; then rm -f "$STATE/low-power"; fi
 return "$KA_POWER_RESULT"
}
case "${1:-status}" in
 enter)
  [ -d "$STATE" ] || { echo 'Start KindleAir before enabling low power' >&2; exit 1; }
  [ ! -f "$STATE/low-power" ] || exit 0
  # Recover an unfinished previous attempt before taking fresh snapshots.
  if [ -f "$STATE/power-governor" ] || [ -f "$STATE/power-light" ]; then restore_power cleanup || exit 1; fi
  KA_GOVERNOR=$(cat "$CPU/scaling_governor" 2>/dev/null)
  case "$KA_GOVERNOR" in
   performance|userspace)
    case " $(cat "$CPU/scaling_available_governors" 2>/dev/null) " in
     *' ondemand '*)
      printf '%s\n' "$KA_GOVERNOR" > "$STATE/power-governor" || exit 1
      if ! printf '%s\n' ondemand > "$CPU/scaling_governor"; then
       rm -f "$STATE/power-governor"; echo 'Warning: adaptive CPU governor unavailable' >&2
      fi
      ;;
    esac
    ;;
  esac
  KA_LIGHT=$(light_get 2>/dev/null)
  case "$KA_LIGHT" in
   ''|*[!0-9]*) echo 'Warning: frontlight control unavailable' >&2;;
   *)
    printf '%s\n' "$KA_LIGHT" > "$STATE/power-light" || { restore_power cleanup; exit 1; }
    if ! light_set 0; then rm -f "$STATE/power-light"; echo 'Warning: could not turn frontlight off' >&2; fi
    ;;
  esac
  touch "$STATE/low-power" || { restore_power cleanup; exit 1; }
  receiver_log_level 0 || echo 'Warning: quiet logging unavailable' >&2
  ;;
 restore) restore_power "${2:-}";;
 status) if [ -f "$STATE/low-power" ]; then echo low; else echo normal; fi;;
 *) echo 'Usage: power-mode.sh enter|restore|status' >&2; exit 2;;
esac
