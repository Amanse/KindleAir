#!/bin/sh
BASE=/mnt/us/extensions/kindleair
STATE=/tmp/kindleair-control
LOG="$BASE/kindleair.log"
notice() {
 KA_MESSAGE=$(printf '%s' "$*" | tr ';' ',' | cut -c 1-25)
 eips 1 2 "KindleAir: $KA_MESSAGE" 2>/dev/null || :
}
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
diagnose() {
 {
  echo 'KindleAir diagnostics'; date; uname -srvm
  cat /etc/prettyversion.txt /mnt/us/system/version.txt 2>/dev/null; echo
  ls -l /lib/ld-linux* /usr/lib/libgstreamer* 2>/dev/null
  echo 'Memory and filesystems'; free; df -h /tmp /mnt/us
  echo 'Firmware mixer probe'; native_sink probe
  echo 'Selected audio properties'
  for prop in audioOutputConnected audioCurrentOutput; do
   lipc-get-prop com.lab126.audiomgrd "$prop" 2>&1
  done
  echo 'Power inhibit'; lipc-get-prop com.lab126.powerd preventScreenSaver 2>&1
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
 start)
  if alive; then notice 'already running'; exit 0; fi
  [ -x /mnt/us/koreader/luajit ] || { notice 'KOReader LuaJIT missing'; exit 1; }
  mkdir "$STATE" 2>/dev/null || { notice 'busy or stale state; Stop first'; exit 1; }
  nohup sh "$BASE/kindleair.sh" run > "$LOG" 2>&1 < /dev/null &
  notice 'starting; check Status in 10 seconds'
  ;;
 stop)
  if alive; then
   kill "$KA_PID"
   i=0; while alive && [ "$i" -lt 10 ]; do sleep 1; i=$((i+1)); done
   if alive; then notice 'shutdown pending; see log'; exit 1; fi
  fi
  rm -f "$STATE/pid" "$STATE/ready"; rmdir "$STATE" 2>/dev/null || :
  notice 'stopped'
  ;;
 status)
  if alive && [ -f "$STATE/ready" ]; then notice 'running as KindleAir (AirPlay 1)'
  elif alive; then notice 'starting; see kindleair.log'
  else notice 'stopped; see kindleair.log'; fi
  ;;
 bluetooth)
  lipc-set-prop -s com.lab126.btfd BTenable '1:1' || { notice 'Bluetooth enable failed'; exit 1; }
  lipc-set-prop -s com.lab126.pillow customDialog '{"name":"bt_wizard_dialog","clientParams":{"show":true,"winmgrModal":true,"replySrc":""}}' || { notice 'Bluetooth dialog unavailable'; exit 1; }
  ;;
 diagnose) diagnose;;
 run)
  echo $$ > "$STATE/pid"
  RT=''; KA_DAEMONS=''; KA_COMPONENTS=''; KA_INHIBIT=0; KA_FIREWALL=0
  cleanup() {
   trap '' TERM INT HUP
   for p in $KA_DAEMONS; do kill "$p" 2>/dev/null || :; done
   for p in $KA_DAEMONS; do wait "$p" 2>/dev/null || :; done
   [ "$KA_INHIBIT" = 0 ] || lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null
   if [ "$KA_FIREWALL" = 1 ]; then
    iptables -D INPUT -i wlan0 -j KINDLEAIR 2>/dev/null || :
    iptables -F KINDLEAIR 2>/dev/null || :
    iptables -X KINDLEAIR 2>/dev/null || :
   fi
   [ -z "$RT" ] || rm -rf "$RT"
   rm -f "$STATE/pid" "$STATE/ready"; rmdir "$STATE" 2>/dev/null || :
  }
  trap 'exit 0' TERM INT HUP
  trap cleanup EXIT
  fail() {
   echo "ERROR: $*"
   for name in dbus avahi sink receiver; do
    if [ -f "$BASE/$name.log" ]; then echo "--- $name ---"; tail -60 "$BASE/$name.log"; fi
   done
   notice "$*"; exit 1
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
  echo 'KindleAir 0.1.3 / Shairport Sync 5.5.1 / classic AirPlay'
  native_sink probe || fail 'firmware mixer unavailable; collect diagnostics'
  RT=$(mktemp -d /tmp/kindleair.XXXXXX) || fail 'cannot allocate runtime'
  tar -xzf "$BASE/runtime.tar.gz" -C "$RT" || fail 'cannot extract runtime'
  export DBUS_SYSTEM_BUS_ADDRESS="unix:path=$RT/bus"
  cat > "$RT/dbus.conf" <<EOF
<busconfig>
 <type>system</type><listen>$DBUS_SYSTEM_BUS_ADDRESS</listen>
 <auth>EXTERNAL</auth>
 <policy user="root"><allow own="*"/><allow send_destination="*"/><allow receive_sender="*"/></policy>
</busconfig>
EOF
  alpine usr/bin/shairport-sync -V || fail 'ARM runtime incompatible; collect diagnostics'
  iptables -N KINDLEAIR || fail 'firewall setup failed'
  KA_FIREWALL=1
  iptables -A KINDLEAIR -p tcp --dport 5000 -j ACCEPT || fail 'AirPlay TCP rule failed'
  iptables -A KINDLEAIR -p udp --dport 6001:6010 -j ACCEPT || fail 'AirPlay UDP rule failed'
  iptables -A KINDLEAIR -p udp --dport 5353 -j ACCEPT || fail 'mDNS rule failed'
  iptables -I INPUT 1 -i wlan0 -j KINDLEAIR || fail 'firewall activation failed'
  "$BASE/component.sh" dbus "$BASE/alpine.sh" "$RT" usr/bin/dbus-daemon --nofork --nopidfile --nosyslog --config-file="$RT/dbus.conf" &
  DBUS_PID=$!; KA_DAEMONS="$DBUS_PID"; KA_COMPONENTS="$DBUS_PID:dbus"
  i=0; while [ ! -S "$RT/bus" ] && [ "$i" -lt 10 ]; do sleep 1; i=$((i+1)); done
  [ -S "$RT/bus" ] || fail 'private D-Bus failed'
  # Avahi uses a fixed runtime directory. Never take over an existing daemon.
  if [ -f /var/run/avahi-daemon/pid ]; then fail 'existing Avahi detected; collect diagnostics'; fi
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
  if [ "$(lipc-get-prop com.lab126.powerd preventScreenSaver 2>/dev/null)" = 0 ]; then
   if lipc-set-prop com.lab126.powerd preventScreenSaver 1; then KA_INHIBIT=1; fi
  fi
  sleep 3
  check_components
  touch "$STATE/ready"
  notice 'running; select KindleAir in AirPlay'
  while :; do
   check_components
   sleep 2
  done
  ;;
 *) echo 'Usage: kindleair.sh start|stop|status|bluetooth|diagnose'; exit 2;;
esac
