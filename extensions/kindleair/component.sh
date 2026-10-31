#!/bin/sh
BASE=/mnt/us/extensions/kindleair
KA_NAME=$1; shift
case "$KA_NAME" in dbus|avahi|sink|receiver) ;; *) exit 64;; esac
exec 3<&0
"$@" <&3 3<&- 2> "$BASE/$KA_NAME.log" &
KA_CHILD=$!
exec 3<&-
shutdown() {
 trap '' TERM INT HUP
 kill "$KA_CHILD" 2>/dev/null || :
 wait "$KA_CHILD" 2>/dev/null || :
 exit 0
}
trap shutdown TERM INT HUP
wait "$KA_CHILD"
KA_RESULT=$?
printf '%s\n' "$KA_RESULT" > "$BASE/$KA_NAME.exit"
printf '%s exited with status %s\n' "$KA_NAME" "$KA_RESULT" >&2
exit "$KA_RESULT"
