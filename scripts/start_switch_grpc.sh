#!/bin/sh

# Start simpl_switch_grpc with 2 ports with the output of the compilation
if [ "$(id -u)" -ne 0 ]; then
  printf "[ERROR] this script requires root privileges"
  exit 1
fi

simple_switch_grpc \
    --log-console \
    --device-id 0 \
    -i 0@veth0 \
    -i 1@veth2 \
    monitor.p4_16.json
