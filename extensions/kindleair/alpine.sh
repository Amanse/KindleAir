#!/bin/sh
KA_RT=$1; KA_BIN=$2; shift 2
# Restrict the account compatibility preload to our private Avahi process.
if [ "$KA_BIN" = usr/sbin/avahi-daemon ]; then
 export LD_PRELOAD="$KA_RT/usr/lib/kindleair-avahi-accounts.so"
fi
# Prefer scalar DSP on this older ARM device while diagnosing startup.
if [ "$KA_BIN" = usr/bin/shairport-sync ]; then
 export SOXR_USE_SIMD=0
fi
exec "$KA_RT/lib/ld-musl-armhf.so.1" --library-path "$KA_RT/lib:$KA_RT/usr/lib" "$KA_RT/$KA_BIN" "$@"
