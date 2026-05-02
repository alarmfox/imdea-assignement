"""
This script connects to the dataplane, automatically injects traffic,
and retrieves the in-network features.

Run this program with:
    sudo PATH=$PATH VIRTUAL_ENV=$VIRTUAL_ENV python3 monitor.py
"""
import os
import sys
import subprocess
import p4runtime_sh.shell as p4sh

# Exit if the script is not run as sudo
if os.geteuid() != 0:
    print("Error: This script requires root privileges to run tcpreplay.")
    print(" Please re-run using: sudo PATH=$PATH VIRTUAL_ENV=$VIRTUAL_ENV python3 monitor.py")
    sys.exit(1)

# Switch Config
my_dev1_addr = "localhost:9559"
my_dev1_id = 0
p4info_txt_fname = 'monitor.p4_16.p4info.txtpb'
p4prog_binary_fname = 'monitor.p4_16.json'

# Traffic Injection Config
TCPREPLAY_IFACE = "veth1"
TCPREPLAY_PCAP = "201302011400.dump"
TCPREPLAY_MULTIPLIER = "0.4"


# ==============================================================================
# 3. MAIN EXECUTION
# ==============================================================================
# Connect and push the pipeline (Clears the switch memory)
p4sh.setup(
    device_id=my_dev1_id,
    grpc_addr=my_dev1_addr,
    election_id=(0, 1),
    config=p4sh.FwdPipeConfig(p4info_txt_fname, p4prog_binary_fname)
)

print("Connected to the switch. Pipeline loaded and ready.")

try:
    print("\n" + "="*60)
    print(f"Injecting traffic via tcpreplay on {TCPREPLAY_IFACE}...")

    # We no longer need 'sudo' in this list because the script itself is running as root
    tcpreplay_cmd = [
        "tcpreplay",
        f"--multiplier={TCPREPLAY_MULTIPLIER}",
        "-i", TCPREPLAY_IFACE,
        TCPREPLAY_PCAP
    ]

    # Execute the command. This blocks until tcpreplay finishes.
    subprocess.run(tcpreplay_cmd, check=True)
    print("Traffic injection complete!")
    print("="*60 + "\n")

    # Read the counters
    print("--- Packet Size Counter ---")
    counters = p4sh.CounterEntry('ingressImpl.pkt_size_hist').read()

    total_packets = 0

    for c in counters:
        size = c.index
        pkt_count = c.data.packet_count

        if pkt_count > 0:
            total_packets += pkt_count
            print(f"Size {size} bytes: {pkt_count} packets")

except subprocess.CalledProcessError as e:
    print(f"\n[!] Error: tcpreplay failed to execute. ({e})")

except FileNotFoundError:
    print("\n[!] Error: 'tcpreplay' command not found. Is it installed?")

finally:
    p4sh.teardown()
    print("\nDisconnected.")
