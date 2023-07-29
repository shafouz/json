#!/bin/bash

zig build test
file=$(find ./zig-cache -name '*test' -type f -printf "%p_%Ts\n" | \
  parallel "printf {}\\\n" | sort -u -t '_' -k 2 | tail -n 1 | \
  sed 's#_.*##')
gdb $file -ex "b main.test.$1" -ex "run"
