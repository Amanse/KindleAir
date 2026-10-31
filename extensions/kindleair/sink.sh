#!/bin/sh
cd /mnt/us/koreader || exit 1
export LD_LIBRARY_PATH=/mnt/us/koreader/libs
exec ./luajit /mnt/us/extensions/kindleair/sink.lua "$@"
