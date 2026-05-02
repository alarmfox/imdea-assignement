#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2019 Andy Fingerhut
#

# This script was copied from the location below, for convenience of
# p4-guide users:
#
# https://github.com/p4lang/behavioral-model/blob/master/tools/veth_teardown.sh
#
# Delete the 2 veth

for idx in 0 1; do
    intf="veth$(($idx*2))"
    if ip link show $intf &> /dev/null; then
        ip link delete $intf type veth
    fi
done
