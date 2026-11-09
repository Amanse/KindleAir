#!/bin/sh
BASE=/mnt/us/extensions/kindleair
STATE=/tmp/kindleair-control
PREF="$BASE/idle-timer.conf"
LAST="$BASE/idle-last.conf"
UPTIME=/proc/uptime
minutes() {
 KA_MINUTES=0
 [ ! -f "$PREF" ] || read -r KA_MINUTES < "$PREF"
 case "$KA_MINUTES" in ''|*[!0-9]*) KA_MINUTES=0;; esac
 [ "$KA_MINUTES" -le 1440 ] 2>/dev/null || KA_MINUTES=0
 printf '%s\n' "$KA_MINUTES"
}
# The KUAL toggle turns the timer back on at the last chosen delay.
last_minutes() {
 KA_LAST=15
 [ ! -f "$LAST" ] || read -r KA_LAST < "$LAST"
 case "$KA_LAST" in ''|*[!0-9]*) KA_LAST=15;; esac
 if [ "$KA_LAST" -ge 1 ] 2>/dev/null && [ "$KA_LAST" -le 1440 ] 2>/dev/null; then :; else KA_LAST=15; fi
 printf '%s\n' "$KA_LAST"
}
now() { read -r KA_UPTIME KA_UNUSED < "$UPTIME"; printf '%s\n' "${KA_UPTIME%%.*}"; }
case "${1:-status}" in
 enabled) [ "$(minutes)" -gt 0 ];;
 set)
  KA_VALUE=${2:-}
  case "$KA_VALUE" in ''|*[!0-9]*) echo 'Choose 0–1440 whole minutes' >&2; exit 2;; esac
  [ "$KA_VALUE" -le 1440 ] 2>/dev/null || exit 2
  # Normalize decimal strings so leading zeros cannot change arithmetic interpretation.
  KA_VALUE=$(printf '%s' "$KA_VALUE" | sed 's/^0*//'); KA_VALUE=${KA_VALUE:-0}
  printf '%s\n' "$KA_VALUE" > "$PREF.new" && mv "$PREF.new" "$PREF" || exit 1
  if [ "$KA_VALUE" -gt 0 ]; then
   printf '%s\n' "$KA_VALUE" > "$LAST.new" && mv "$LAST.new" "$LAST" || :
  fi
  if [ -d "$STATE" ]; then now > "$STATE/idle-reset"; rm -f "$STATE/idle-status"; fi
  ;;
 status) minutes;;
 last) last_minutes;;
 check)
  KA_LIMIT=$(minutes)
  if [ "$KA_LIMIT" = 0 ]; then rm -f "$STATE/idle-status"; exit 0; fi
  KA_NOW=$(now)
  [ -r "$STATE/media-state" ] || exit 0
  if ! read -r KA_OBSERVED KA_AUDIO KA_POSITION < "$STATE/media-state"; then exit 0; fi
  case "$KA_OBSERVED:$KA_AUDIO:$KA_POSITION" in *[!0-9:]*) exit 0;; esac
  [ -n "$KA_OBSERVED" ] && [ -n "$KA_AUDIO" ] && [ -n "$KA_POSITION" ] || exit 0
  # Stale or invalid telemetry is unknown, never evidence that playback is idle.
  [ "$KA_OBSERVED" -le "$KA_NOW" ] && [ "$KA_AUDIO" -le "$KA_OBSERVED" ] || exit 0
  [ $((KA_NOW - KA_OBSERVED)) -le 30 ] || exit 0
  if [ -f "$STATE/idle-reset" ]; then
   read -r KA_RESET < "$STATE/idle-reset"
   case "$KA_RESET" in ''|*[!0-9]*) KA_RESET=0;; esac
   if [ "$KA_RESET" -le "$KA_NOW" ] && [ "$KA_RESET" -gt "$KA_AUDIO" ]; then KA_AUDIO=$KA_RESET; fi
  fi
  KA_ELAPSED=$((KA_NOW - KA_AUDIO))
  KA_REMAINING=$((KA_LIMIT * 60 - KA_ELAPSED))
  printf '%s\n' "$KA_REMAINING" > "$STATE/idle-status"
  if [ "$KA_REMAINING" -le 0 ]; then exit 10; fi
  ;;
 *) echo 'Usage: idle-control.sh enabled|set MINUTES|status|last|check' >&2; exit 2;;
esac
