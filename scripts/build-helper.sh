#!/bin/sh
set -eu
KA_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KA_CC=${CC:-arm-linux-musleabihf-gcc}
mkdir -p "$KA_ROOT/build"
"$KA_CC" -march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=hard \
 -O2 -fPIC -ffreestanding -nostdinc -nostdlib -shared -Wall -Wextra -Werror \
 -Wl,-soname,kindleair-avahi-accounts.so \
 "$KA_ROOT/extensions/kindleair/avahi-accounts.c" \
 -o "$KA_ROOT/build/kindleair-avahi-accounts.so"
