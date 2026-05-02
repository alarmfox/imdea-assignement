#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2019 Andy Fingerhut
#

# This script was copied from the location below, for convenience of
# p4-guide users:
#
# https://github.com/p4lang/behavioral-model/blob/master/tools/veth_teardown.sh
#
# Delete the 4 veth

if [ "$(id -u)" -ne 0 ]; then
  printf "[ERROR] this script requires root privileges"
  exit 1
fi

for idx in 0 1 2 3; do
    intf="veth$(($idx*2))"
    if ip link show $intf &> /dev/null; then
        ip link delete $intf type veth
    fi
done
