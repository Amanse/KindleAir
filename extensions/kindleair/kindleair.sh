#!/bin/sh
BASE=/mnt/us/extensions/kindleair
STATE=/tmp/kindleair-control
LOG="$BASE/kindleair.log"
SLEEP_PREF="$BASE/keep-awake.conf"
LOW_POWER_PREF="$BASE/low-power.conf"
# KUAL caches the parsed menu. Settings commands drop it so state labels and
# checkbox entries are re-evaluated the next time the menu is drawn.
MENU_CACHE=/var/tmp/KUAL.cache
notice() {
 KA_MESSAGE=$(printf '%s' "$*" | tr ';' ',' | cut -c 1-25)
 eips 1 2 "KindleAir: $KA_MESSAGE" 2>/dev/null || :
}
settings_notice() {
 eips 1 2 'KindleAir settings' 2>/dev/null || :
 eips 1 3 "Low power mode: $1" 2>/dev/null || :
 eips 1 4 "Keep awake: $2" 2>/dev/null || :
 eips 1 5 "Auto sleep: $3" 2>/dev/null || :
}
menu_cache_forget() { rm -f "$MENU_CACHE" 2>/dev/null || :; }
native_sink() { (cd /mnt/us/koreader && LD_LIBRARY_PATH=/mnt/us/koreader/libs ./luajit "$BASE/sink.lua" "$@"); }
alive() {
 [ -f "$STATE/pid" ] || return 1
 KA_PID=$(cat "$STATE/pid")
 case "$KA_PID" in ''|*[!0-9]*) return 1;; esac
 kill -0 "$KA_PID" 2>/dev/null || return 1
 tr '\000' ' ' < "/proc/$KA_PID/cmdline" 2>/dev/null | grep -q 'kindleair.sh run'
}
alpine() {
 KA_BIN=$1; shift
 "$RT/lib/ld-musl-armhf.so.1" --library-path "$RT/lib:$RT/usr/lib" "$RT/$KA_BIN" "$@"
}
# An absent preference preserves the original keep-awake default.
keep_awake_enabled() { [ ! -f "$SLEEP_PREF" ] || [ "$(cat "$SLEEP_PREF")" != 0 ]; }
release_sleep_inhibit() {
 [ -f "$STATE/sleep-owned" ] || return 0
 native_lipc_set com.lab126.powerd preventScreenSaver 0 || return 1
 rm -f "$STATE/sleep-owned"
}
apply_sleep_setting() {
 if keep_awake_enabled || "$BASE/idle-control.sh" enabled; then
  KA_SLEEP_CURRENT=$(native_lipc_get com.lab126.powerd preventScreenSaver 2>/dev/null) || return 1
  case "$KA_SLEEP_CURRENT" in
   0)
    native_lipc_set com.lab126.powerd preventScreenSaver 1 || return 1
    touch "$STATE/sleep-owned"
    ;;
   1) :;; # Do not claim an inhibitor that another app already held.
   *) return 1;;
  esac
 else
  release_sleep_inhibit
 fi
}
save_sleep_setting() {
 printf '%s\n' "$1" > "$SLEEP_PREF.new" && mv "$SLEEP_PREF.new" "$SLEEP_PREF" || return 1
 menu_cache_forget
 if alive; then apply_sleep_setting || return 1; fi
}
preferred_power_mode() {
 if [ -f "$LOW_POWER_PREF" ] && [ "$(cat "$LOW_POWER_PREF")" = 1 ]; then echo low; else echo normal; fi
}
save_power_setting() {
 printf '%s\n' "$1" > "$LOW_POWER_PREF.new" && mv "$LOW_POWER_PREF.new" "$LOW_POWER_PREF" || return 1
 menu_cache_forget
 if alive; then
  if [ "$1" = 1 ]; then "$BASE/power-mode.sh" enter; else "$BASE/power-mode.sh" restore; fi
 fi
}
native_lipc_get() { (unset DBUS_SYSTEM_BUS_ADDRESS; lipc-get-prop "$@"); }
native_lipc_set() { (unset DBUS_SYSTEM_BUS_ADDRESS; lipc-set-prop "$@"); }
# Remove only KindleAir's own chain, whether or not a supervisor is still alive.
remove_firewall() {
 iptables -D INPUT -i wlan0 -j KINDLEAIR 2>/dev/null || :
 iptables -F KINDLEAIR 2>/dev/null || :
 iptables -X KINDLEAIR 2>/dev/null || :
}
# KindleAir processes left behind by a supervisor killed with SIGKILL. Match
# the executable's own command line, never an arbitrary string, so a shell that
# merely mentions these paths is not signalled.
pid_is_kindleair() {
 case "$1" in ''|*[!0-9]*) return 1;; esac
 [ -r "/proc/$1/cmdline" ] || return 1
 KA_PROC_CMDLINE=$(cat "/proc/$1/cmdline" 2>/dev/null | tr '\000' ' ') || return 1
 set -f
 set -- $KA_PROC_CMDLINE
 set +f
 case "$1" in /tmp/kindleair.*) return 0;; esac
 case "$2" in "$BASE/component.sh"|"$BASE/sink.sh"|"$BASE/sink.lua") return 0;; esac
 return 1
}
kill_orphans() {
 KA_STALE=0
 for dir in /proc/[0-9]*; do
  KA_ORPHAN=${dir#/proc/}
  [ "$KA_ORPHAN" = "$$" ] && continue
  if pid_is_kindleair "$KA_ORPHAN"; then
   KA_STALE=1
   kill "$KA_ORPHAN" 2>/dev/null || :
  fi
 done
 [ "$KA_STALE" = 1 ] || return 0
 sleep 1
 for dir in /proc/[0-9]*; do
  KA_ORPHAN=${dir#/proc/}
  [ "$KA_ORPHAN" = "$$" ] && continue
  pid_is_kindleair "$KA_ORPHAN" && kill -9 "$KA_ORPHAN" 2>/dev/null
 done
}
# Recover from a crash, a forced kill or a session that died during startup.
# Hardware snapshots, the sleep inhibitor, children and firewall rules are ours.
reset_session_state() {
 kill_orphans
 "$BASE/power-mode.sh" restore cleanup 2>/dev/null || :
 release_sleep_inhibit || :
 remove_firewall
 if [ -f "$STATE/runtime" ]; then
  KA_OLD_RT=$(cat "$STATE/runtime" 2>/dev/null)
  case "$KA_OLD_RT" in /tmp/kindleair.*) rm -rf "$KA_OLD_RT";; esac
 fi
 rm -rf "$STATE"
}
request_idle_sleep() {
 # Respect other applications and never toggle an already-inactive Kindle awake.
 if [ "$(native_lipc_get com.lab126.powerd preventScreenSaver 2>/dev/null)" = 0 ] && \
    [ "$(native_lipc_get com.lab126.powerd state 2>/dev/null)" = active ]; then
  echo 'Idle timer: receiver stopped; requesting firmware sleep'
  native_lipc_set com.lab126.powerd powerButton 1 || echo 'Warning: firmware sleep request failed'
 else echo 'Idle timer: receiver stopped; sleep inhibited elsewhere or device already inactive'; fi
}
diagnose() {
 {
  echo 'KindleAir diagnostics'; date; uname -srvm
  cat /etc/prettyversion.txt /mnt/us/system/version.txt 2>/dev/null; echo
  ls -l /lib/ld-linux* /usr/lib/libgstreamer* 2>/dev/null
  echo 'Memory and filesystems'; free; df -h /tmp /mnt/us
  echo 'Firmware mixer probe'; native_sink probe
  echo 'Selected audio properties'
  for prop in audioOutputConnected audioCurrentOutput; do
   native_lipc_get com.lab126.audiomgrd "$prop" 2>&1
  done
  echo 'Auto sleep minutes'; "$BASE/idle-control.sh" status
  echo 'Auto sleep last delay'; "$BASE/idle-control.sh" last
  echo 'Idle telemetry'; cat "$STATE/media-state" "$STATE/idle-status" 2>/dev/null
  echo 'Keep-awake preference'; if keep_awake_enabled; then echo enabled; else echo disabled; fi
  echo 'Default power mode'; preferred_power_mode
  echo 'Power mode'; "$BASE/power-mode.sh" status
  echo 'Power inhibit'; native_lipc_get com.lab126.powerd preventScreenSaver 2>&1
  echo 'KindleAir firewall chain'; iptables -S KINDLEAIR 2>&1
  echo 'Audio tools'
  for tool in gst-launch-0.10 gst-launch-1.0 gst-inspect-0.10 gst-inspect-1.0 aplay lipc-probe; do command -v "$tool"; done
  echo 'Network addresses'; ip -4 addr show 2>/dev/null || ifconfig
  echo 'Existing mDNS processes'; ps | grep -E 'avahi|mdns|mDNS' | grep -v grep
  echo 'Recent KindleAir log'; tail -100 "$LOG" 2>/dev/null
  for name in dbus avahi sink receiver; do
   echo "Component $name"; cat "$BASE/$name.exit" 2>/dev/null; tail -80 "$BASE/$name.log" 2>/dev/null
  done
 } > "$BASE/diagnostics.txt" 2>&1
 notice 'diagnostics saved'
}
case "${1:-status}" in
 start|start-low)
  KA_START_MODE=$(preferred_power_mode)
  [ "$1" != start-low ] || KA_START_MODE=low
  if alive && [ "$KA_START_MODE" = low ]; then
   "$BASE/power-mode.sh" enter || { notice 'low power setup failed'; exit 1; }
   notice 'low power enabled'; exit 0
  fi
  if alive; then notice 'already running'; exit 0; fi
  [ -x /mnt/us/koreader/luajit ] || { notice 'KOReader LuaJIT missing'; exit 1; }
  # Leftovers from a crash or forced kill must not block every later start.
  # Give a concurrent Start a moment to publish its pid before recovering.
  if [ -d "$STATE" ]; then
   sleep 1
   if alive; then notice 'already running'; exit 0; fi
   reset_session_state
  fi
  mkdir "$STATE" 2>/dev/null || { notice 'cannot create state dir'; exit 1; }
  nohup sh "$BASE/kindleair.sh" run "$KA_START_MODE" > "$LOG" 2>&1 < /dev/null &
  notice 'starting; wait 10s'
  ;;
 stop)
  if alive; then
   kill "$KA_PID"
   i=0; while alive && [ "$i" -lt 10 ]; do sleep 1; i=$((i+1)); done
   if alive; then notice 'shutdown pending; see log'; exit 1; fi
  fi
  reset_session_state
  notice 'stopped'
  ;;
 power-low)
  save_power_setting 1 || { notice 'power setting failed'; exit 1; }
  notice 'low power mode ON'
  ;;
 power-normal)
  save_power_setting 0 || { notice 'power setting failed'; exit 1; }
  notice 'low power mode OFF'
  ;;
 power-status)
  if [ "$(preferred_power_mode)" = low ]; then notice 'low power mode ON'; else notice 'low power mode OFF'; fi
  ;;
 normal-power)
  "$BASE/power-mode.sh" restore || { notice 'power restore failed'; exit 1; }
  notice 'normal power restored'
  ;;
 settings-status)
  if [ "$(preferred_power_mode)" = low ]; then KA_SET_LP=On; else KA_SET_LP=Off; fi
  if keep_awake_enabled; then KA_SET_KA=On; else KA_SET_KA=Off; fi
  KA_SET_IDLE=$("$BASE/idle-control.sh" status)
  if [ "$KA_SET_IDLE" = 0 ]; then KA_SET_IDLE=Off; else KA_SET_IDLE="On, $KA_SET_IDLE min"; fi
  settings_notice "$KA_SET_LP" "$KA_SET_KA" "$KA_SET_IDLE"
  ;;
 status)
  if alive && [ -f "$STATE/ready" ] && [ -f "$STATE/low-power" ]; then notice 'running - low power'
  elif alive && [ -f "$STATE/ready" ]; then notice 'running (AirPlay)'
  elif alive; then notice 'starting; see log'
  else notice 'stopped; see log'; fi
  ;;
 bluetooth)
  native_lipc_set -s com.lab126.btfd BTenable '1:1' || { notice 'Bluetooth enable failed'; exit 1; }
  native_lipc_set -s com.lab126.pillow customDialog '{"name":"bt_wizard_dialog","clientParams":{"show":true,"winmgrModal":true,"replySrc":""}}' || { notice 'Bluetooth dialog failed'; exit 1; }
  ;;
 sleep-on)
  save_sleep_setting 1 || { notice 'sleep setting failed'; exit 1; }
  notice 'keep awake enabled'
  ;;
 sleep-off)
  save_sleep_setting 0 || { notice 'sleep setting failed'; exit 1; }
  if "$BASE/idle-control.sh" enabled; then notice 'auto sleep controls sleep'; else notice 'normal sleep allowed'; fi
  ;;
 sleep-status)
  if "$BASE/idle-control.sh" enabled; then notice 'auto sleep controls sleep'
  elif keep_awake_enabled; then notice 'keep awake is ON'; else notice 'keep awake is OFF'; fi
  ;;
 resync)
  alive && [ -f "$STATE/ready" ] || { notice 'start receiver first'; exit 1; }
  rm -f "$STATE/resync.done"
  : > "$STATE/resync.request"
  KA_RESYNC_WAIT=0
  while [ ! -f "$STATE/resync.done" ] && [ "$KA_RESYNC_WAIT" -lt 8 ]; do sleep 1; KA_RESYNC_WAIT=$((KA_RESYNC_WAIT + 1)); done
  [ -f "$STATE/resync.done" ] || { notice 'resync pending - see log'; exit 1; }
  notice 'audio queue resynced'
  ;;
 idle-minutes)
  "$BASE/idle-control.sh" set "${2:-}" || { notice 'invalid idle minutes'; exit 1; }
  menu_cache_forget
  if alive; then apply_sleep_setting || { notice 'sleep setting failed'; exit 1; }; fi
  if [ "${2:-}" = 0 ]; then notice 'auto sleep OFF'; else notice "auto sleep: ${2:-} min"; fi
  ;;
 idle-toggle)
  if "$BASE/idle-control.sh" enabled; then
   "$BASE/idle-control.sh" set 0 || { notice 'auto sleep change failed'; exit 1; }
   notice 'auto sleep OFF'
  else
   KA_IDLE_DELAY=$("$BASE/idle-control.sh" last)
   "$BASE/idle-control.sh" set "$KA_IDLE_DELAY" || { notice 'auto sleep change failed'; exit 1; }
   notice "auto sleep ON, $KA_IDLE_DELAY min"
  fi
  menu_cache_forget
  if alive; then apply_sleep_setting || notice 'sleep setting failed'; fi
  ;;
 idle-status)
  KA_IDLE_MINUTES=$("$BASE/idle-control.sh" status)
  if [ "$KA_IDLE_MINUTES" = 0 ]; then notice 'auto sleep OFF'; else notice "auto sleep: $KA_IDLE_MINUTES min"; fi
  ;;
 diagnose) diagnose;;
 run)
  KA_RUN_MODE=${2:-normal}
  case "$KA_RUN_MODE" in low|normal) ;; *) echo "Unknown run mode: $KA_RUN_MODE"; exit 2;; esac
  echo $$ > "$STATE/pid"
  RT=''; KA_DAEMONS=''; KA_COMPONENTS=''; KA_TIMER_PID=''; KA_SLEEP_ON_EXIT=0
  cleanup() {
   trap '' TERM INT HUP
   if [ -n "$KA_TIMER_PID" ]; then kill "$KA_TIMER_PID" 2>/dev/null || :; wait "$KA_TIMER_PID" 2>/dev/null || :; fi
   for p in $KA_DAEMONS; do kill "$p" 2>/dev/null || :; done
   for p in $KA_DAEMONS; do wait "$p" 2>/dev/null || :; done
   "$BASE/power-mode.sh" restore cleanup || echo "Warning: could not restore power settings"
   release_sleep_inhibit || echo "Warning: could not release sleep inhibitor"
   remove_firewall
   [ -z "$RT" ] || rm -rf "$RT"
   rm -rf "$STATE"
   if [ "$KA_SLEEP_ON_EXIT" = 1 ]; then request_idle_sleep; fi
  }
  trap 'exit 0' TERM INT HUP
  trap cleanup EXIT
  fail() {
   echo "ERROR: $*"
   for name in dbus avahi sink receiver; do
    if [ -f "$BASE/$name.log" ]; then echo "--- $name ---"; tail -60 "$BASE/$name.log"; fi
   done
   notice 'failed; see kindleair.log'; exit 1
  }
  check_components() {
   for entry in $KA_COMPONENTS; do
    p=${entry%%:*}; name=${entry#*:}
    if ! kill -0 "$p" 2>/dev/null; then
     wait "$p" 2>/dev/null; rc=$?
     echo "Component $name stopped with exit status $rc"
     fail "$name exit $rc - see log"
    fi
   done
  }
  for name in dbus avahi sink receiver; do rm -f "$BASE/$name.log" "$BASE/$name.exit"; done
  echo 'KindleAir 0.2.0-beta.4 / Shairport Sync 5.5.1 / classic AirPlay'
  native_sink probe || fail 'firmware mixer unavailable; collect diagnostics'
  RT=$(mktemp -d /tmp/kindleair.XXXXXX) || fail 'cannot allocate runtime'
  tar -xzf "$BASE/runtime.tar.gz" -C "$RT" || fail 'cannot extract runtime'
  printf '%s\n' "$RT" > "$STATE/runtime"
  export DBUS_SYSTEM_BUS_ADDRESS="unix:path=$RT/bus"
  cat > "$RT/dbus.conf" <<EOF
<busconfig>
 <type>system</type><listen>$DBUS_SYSTEM_BUS_ADDRESS</listen>
 <auth>EXTERNAL</auth>
 <policy user="root"><allow own="*"/><allow send_destination="*"/><allow receive_sender="*"/></policy>
</busconfig>
EOF
  alpine usr/bin/shairport-sync -V || fail 'ARM runtime incompatible; collect diagnostics'
  # A chain left behind by a crash must not block this session.
  remove_firewall
  iptables -N KINDLEAIR || fail 'firewall setup failed'
  iptables -A KINDLEAIR -p tcp --dport 5000 -j ACCEPT || fail 'AirPlay TCP rule failed'
  iptables -A KINDLEAIR -p udp --dport 6001:6010 -j ACCEPT || fail 'AirPlay UDP rule failed'
  iptables -A KINDLEAIR -p udp --dport 5353 -j ACCEPT || fail 'mDNS rule failed'
  iptables -I INPUT 1 -i wlan0 -j KINDLEAIR || fail 'firewall activation failed'
  "$BASE/component.sh" dbus "$BASE/alpine.sh" "$RT" usr/bin/dbus-daemon --nofork --nopidfile --nosyslog --config-file="$RT/dbus.conf" &
  DBUS_PID=$!; KA_DAEMONS="$DBUS_PID"; KA_COMPONENTS="$DBUS_PID:dbus"
  i=0; while [ ! -S "$RT/bus" ] && [ "$i" -lt 10 ]; do sleep 1; i=$((i+1)); done
  [ -S "$RT/bus" ] || fail 'private D-Bus failed'
  # Avahi uses a fixed runtime directory. Never take over a live daemon, but a
  # pid file and socket left by a killed daemon are safe to remove.
  if [ -f /var/run/avahi-daemon/pid ]; then
   KA_OLD_AVAHI=$(cat /var/run/avahi-daemon/pid 2>/dev/null)
   case "$KA_OLD_AVAHI" in ''|*[!0-9]*) KA_OLD_AVAHI=0;; esac
   if [ "$KA_OLD_AVAHI" != 0 ] && kill -0 "$KA_OLD_AVAHI" 2>/dev/null; then
    fail 'existing Avahi detected; collect diagnostics'
   fi
   echo 'Removing stale Avahi pid file and socket'
   rm -f /var/run/avahi-daemon/pid /var/run/avahi-daemon/socket
  fi
  cat > "$RT/avahi.conf" <<EOF
[server]
host-name=kindleair
use-ipv4=yes
use-ipv6=no
enable-dbus=yes
disallow-other-stacks=no
[wide-area]
enable-wide-area=no
[publish]
publish-hinfo=no
publish-workstation=no
[reflector]
enable-reflector=no
EOF
  "$BASE/component.sh" avahi "$BASE/alpine.sh" "$RT" usr/sbin/avahi-daemon --no-drop-root --no-chroot --no-rlimits --debug -f "$RT/avahi.conf" &
  AVAHI_PID=$!; KA_DAEMONS="$KA_DAEMONS $AVAHI_PID"; KA_COMPONENTS="$KA_COMPONENTS $AVAHI_PID:avahi"
  sleep 3
  check_components
  mkfifo "$RT/audio" || fail 'cannot create audio pipe'
  "$BASE/component.sh" sink "$BASE/sink.sh" stream "$RT/audio" &
  SINK_PID=$!; KA_DAEMONS="$KA_DAEMONS $SINK_PID"; KA_COMPONENTS="$KA_COMPONENTS $SINK_PID:sink"
  "$BASE/component.sh" receiver "$BASE/alpine.sh" "$RT" usr/bin/shairport-sync -c "$BASE/shairport-sync.conf" --metadata-pipename="$RT/metadata" -v > "$RT/audio" &
  AIR_PID=$!; KA_DAEMONS="$KA_DAEMONS $AIR_PID"; KA_COMPONENTS="$KA_COMPONENTS $AIR_PID:receiver"
  apply_sleep_setting || echo "Warning: could not apply sleep setting"
  sleep 3
  check_components
  if [ "$KA_RUN_MODE" = low ]; then
   "$BASE/power-mode.sh" enter || fail 'low power setup failed'
  fi
  touch "$STATE/ready"
  notice 'running; select KindleAir'
  KA_SLEEP_SECONDS=0
  while :; do
   check_components
   "$BASE/idle-control.sh" check
   KA_IDLE_RESULT=$?
   if [ "$KA_IDLE_RESULT" = 10 ]; then
    echo 'Idle timer expired: restoring settings and stopping receiver'
    KA_SLEEP_ON_EXIT=1
    exit 0
   fi
   if [ -f "$STATE/low-power" ]; then KA_POLL_SECONDS=10; else KA_POLL_SECONDS=2; fi
   if [ "$KA_SLEEP_SECONDS" -ge 30 ]; then
    apply_sleep_setting || echo "Warning: could not refresh sleep setting"
    KA_SLEEP_SECONDS=0
   fi
   sleep "$KA_POLL_SECONDS" &
   KA_TIMER_PID=$!
   wait "$KA_TIMER_PID"
   KA_TIMER_PID=''
   KA_SLEEP_SECONDS=$((KA_SLEEP_SECONDS + KA_POLL_SECONDS))
  done
  ;;
 *) echo 'Usage: kindleair.sh start|start-low|stop|normal-power|power-low|power-normal|power-status|settings-status|status|bluetooth|sleep-on|sleep-off|sleep-status|resync|idle-toggle|idle-minutes MINUTES|idle-status|diagnose'; exit 2;;
esac
