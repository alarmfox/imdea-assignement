#!/bin/sh

# Create a CSV filtering the .dump file. Results will be saved in FILENAME.csv

if [ -z "$1" ]; then
    echo "Usage: $0 <filename.pcap>"
    exit 1
fi

FILENAME_BASE="${1%.*}"

tshark -r $1 -T fields \
  -e frame.number \
  -e frame.time_relative \
  -e frame.time_delta \
  -e frame.len \
  -e ip.src -e ip.dst \
  -e ip.proto \
  -e tcp.srcport -e tcp.dstport \
  -e udp.srcport -e udp.dstport \
  -E header=y -E separator=, -E quote=d > ${FILENAME_BASE}.csv
