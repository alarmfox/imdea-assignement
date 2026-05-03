import csv
import os
import sys
import subprocess
import p4runtime_sh.shell as p4sh

usage = f"""
This script connects to the dataplane, automatically injects traffic,
and retrieves the in-network features.

Run this program with:
    sudo PATH=$PATH VIRTUAL_ENV=$VIRTUAL_ENV python3 {sys.argv[0]}
"""

# Exit if the script is not run as sudo
if os.geteuid() != 0:
    print("Error: This script requires root privileges to run tcpreplay.")
    print(usage)
    sys.exit(1)

# Switch Config
my_dev1_addr = "localhost:9559"
my_dev1_id = 0
p4info_txt_fname = "monitor.p4_16.p4info.txtpb"
p4prog_binary_fname = "monitor.p4_16.json"

# Traffic Injection Config
TCPREPLAY_IFACE = "veth1"
TCPREPLAY_PCAP = "dataset/201302011400-100000.dump"
TCPREPLAY_MULTIPLIER = "0.01"

# Output files
p4_packet_sizes_filename = "dataset/p4_packet_sizes.csv"
p4_flow_data_filename = "dataset/p4_flow_stats.csv"

p4sh.setup(
    device_id=my_dev1_id,
    grpc_addr=my_dev1_addr,
    election_id=(0, 1),
    config=p4sh.FwdPipeConfig(p4info_txt_fname, p4prog_binary_fname),
)

print("Connected to the switch.")


def handle_packet_size(fname: str) -> None:
    """
    Extract the packet sizes from the counter
    """

    print("--- Proessing packet size ---")
    counters = p4sh.CounterEntry("ingressImpl.pkt_size_hist").read()

    total_packets = 0
    with open(fname, mode="w", newline="") as file:
        writer = csv.writer(file)
        # Write the header row
        writer.writerow(["packet_size", "count"])

        for c in counters:
            size = c.index
            pkt_count = c.data.packet_count

            if pkt_count > 0:
                total_packets += pkt_count
                # Write the data row to the CSV
                writer.writerow([size, pkt_count])

    print(f"--- Processed {total_packets} packets. Data saved to {fname} ---")


def handle_flow_counters(fname: str, thrift_port: int = 9090) -> None:
    """
    Retrieves flow timestamps from BMv2 registers via Thrift CLI,
    calculates duration, and saves the data to a CSV.
    """
    print(f"--- Fetching Flow Data via Thrift (Port {thrift_port}) ---")

    def read_register(register_name: str) -> list:
        """
        This function has been generated with the help of an LLM.
        It runs the thrift CLI to read a register of the BMv2
        """
        # Executes the CLI command and captures output
        cmd = f'echo "register_read {register_name}" | simple_switch_CLI --thrift-port {thrift_port}'
        try:
            output = subprocess.check_output(
                cmd, shell=True, stderr=subprocess.STDOUT
            ).decode("utf-8")

            # Find the line containing our data
            # Looking for "register_name= 0, 0, 123, ..."
            for line in output.splitlines():
                if f"{register_name}=" in line:
                    # Split at '=' and take the second part (the numbers)
                    raw_values = line.split("=")[-1].strip()
                    # Split by commas and convert to integers
                    return [
                        int(val.strip()) for val in raw_values.split(",") if val.strip()
                    ]
            return []
        except Exception as e:
            print(f"Error parsing register {register_name}: {e}")
            return []

    # Read the 3 registers
    starts = read_register("ingressImpl.flow_start_ts")
    lasts = read_register("ingressImpl.flow_last_ts")
    protos = read_register("ingressImpl.flow_proto")
    counts = p4sh.CounterEntry("ingressImpl.flow_tracker").read()

    active_flows = 0

    # Save flows to CSV
    with open(fname, mode="w", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(["flow_index", "protocol", "duration_us", "packet_count"])

        for idx, (s, l, p, c) in enumerate(zip(starts, lasts, protos, counts)):
            if s > 0:
                writer.writerow([idx, p, l - s, c.data.packet_count])

    print(f"--- Processed {active_flows} active flows. Data saved to {fname} ---")


def main() -> None:
    try:
        print("\n" + "=" * 60)
        print(f"Injecting traffic via tcpreplay on {TCPREPLAY_IFACE}...")
        print(f"pcap={TCPREPLAY_PCAP}, multiplier={TCPREPLAY_MULTIPLIER}")

        tcpreplay_cmd = [
            "tcpreplay",
            f"--multiplier={TCPREPLAY_MULTIPLIER}",
            "-i",
            TCPREPLAY_IFACE,
            TCPREPLAY_PCAP,
        ]

        # Execute the command. This blocks until tcpreplay finishes.
        subprocess.run(tcpreplay_cmd, check=True)
        print("Traffic injection complete!")
        print("=" * 60 + "\n")

        handle_packet_size(p4_packet_sizes_filename)
        handle_flow_counters(p4_flow_data_filename)

    except subprocess.CalledProcessError as e:
        print(f"\n[!] Error: a subprocess failed to execute. ({e})")

    except FileNotFoundError as e:
        print(f"\n[!] Error: 'tcpreplay' command not found. Is it installed? {e}")

    finally:
        p4sh.teardown()
        print("\nDisconnected.")


if __name__ == "__main__":
    main()
