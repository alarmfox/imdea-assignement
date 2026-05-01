import argparse
import io
import pathlib
import pandas as pd
import subprocess


parser = argparse.ArgumentParser(
    prog="prepare_pcap",
    description="This script creates a TSV from the provided PCAP adding flow information.",
    epilog="Text at the bottom of help",
)

parser.add_argument("filename", help="Path to PCAP file")
parser.add_argument(
    "-c",
    "--count",
    help="Cut packets to the provided value, if present",
    required=False,
)


def main(pcap: str, count: int | None) -> None:
    """
    Use tshark to convert the provided PCAP in a CSV and extract flow information
    """

    pcap_path = pathlib.Path(pcap)
    suffix = "-full" if count is None else f"-{count}"
    temp_csv = pcap_path.parent / f"{pcap_path.stem}_temp.csv"
    output_file = pcap_path.parent / f"{pcap_path.stem}{suffix}.csv"

    fields = [
        "frame.number",
        "frame.time_relative",
        "frame.time_delta",
        "frame.len",
        "ip.src",
        "ip.dst",
        "ip.proto",
        "tcp.srcport",
        "tcp.dstport",
        "udp.srcport",
        "udp.dstport"
    ]

    tshark_cmd = [
        "tshark", "-r", pcap,
        "-T", "fields",
        "-E", "header=y",
        "-E", "separator=,",
        "-E", "occurrence=f",
    ]

    if count is not None:
        tshark_cmd += ["-c", str(count)]

    for field in fields:
        tshark_cmd.extend(["-e", field])

    print("The following command will be executed:\n\n", " ".join(tshark_cmd), sep="", end="\n\n")

    print(f"Extracting data from PCAP to temporary file: {temp_csv} ...")
    with open(temp_csv, "wb") as f:
        subprocess.run(tshark_cmd, stdout=f, check=True)

    print("Loading data into Pandas...")
    df = pd.read_csv(temp_csv)

    df['port.src'] = df['tcp.srcport'].fillna(df['udp.srcport'])
    df['port.dst'] = df['tcp.dstport'].fillna(df['udp.dstport'])

    df.drop(['tcp.srcport', 'tcp.dstport', 'udp.srcport', 'udp.dstport'], axis=1, inplace=True)

    df['port.src'] = df['port.src'].fillna(0).astype(int)
    df['port.dst'] = df['port.dst'].fillna(0).astype(int)

    print("Generating flow ids. This may take some time...")
    df["flow_id"] = df.set_index(["ip.src", "ip.dst", "ip.proto", "port.dst", "port.src"]).index.factorize()[0]

    print("Saving data to", output_file)
    df.to_csv(output_file)

    print(f"Removing temporary file {temp_csv}")
    temp_csv.unlink()

if __name__ == "__main__":
    args = parser.parse_args()
    main(args.filename, args.count)
