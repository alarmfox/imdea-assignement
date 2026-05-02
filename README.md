# Network Traffic Characterization - IMDEA Assessment

Traffic analysis project for the IMDEA Networks Institute doctoral position. This repo implements software-based statistical analysis and in-network feature extraction using P4.

## AI Disclosure
LLMs were used to assist with P4 boilerplate code and documentation structure. All implementations and analysis were manually verified and refined.

## Project Structure
- `analysis.ipynb`: Statistical analysis, distribution fitting, and Task I vs. Task II results comparison.
- `monitor.p4_16.p4`: P4 source for the bmv2 switch (packet size tracking).
- `monitor.py`: Control plane script. Handles traffic injection (`tcpreplay`) and counter collection.
- `scripts/`:
  - `prepare_pcap.py`: Converts PCAP to CSV with flow aggregation.
  - `veth_setup.sh` / `veth_teardown.sh`: Manage virtual ethernet pairs.
  - `start_switch_grpc.sh`: Launches the BMv2 software switch.
- `Makefile`: Compiles P4 code.
- `dataset/`: Input traces and generated CSVs.
- `figures/`: Analysis plots.

## Setup

### Python Environment

The code has been tested with Python 3.14. To ensure reproducibility users can use [uv]("https://docs.astral.sh/uv/getting-started/installation/"):
```sh
uv venv --python 3.14
source .venv/bin/activate
uv pip install -r requirements.txt
```

### P4 Environment
Requires an Ubuntu 24.04 VM with `bmv2`, `p4c`, `tshark`, and `tcpreplay`.
Reference: [P4 Tutorial VM Setup](https://github.com/p4lang/tutorials/tree/master/vm-ubuntu-24.04).

## Execution

### Task 1: Software-based Analysis
1. **Pre-process PCAP**:
   ```bash
   python scripts/prepare_pcap.py <path-to-pcap> [-c <packet-limit>]
   ```
   Uses `tshark` to extract fields and group packets into 5-tuple flows. Generates a CSV in `dataset/`.

2. **Run Analysis**:
   Execute `analysis.ipynb` until the "Conclusion" section to view distribution fitting (bimodal) and flow metrics.

### Task 2: In-Network Extraction (P4)
The P4 program implements a 2-port forwarder (Port 0 -> Port 1) with histogram counters for packet sizes.

1. **Truncate Trace**:
   Cut the original dataset to 100k packets for the bmv2 simulation:
   ```bash
   mkdir dataset
   tshark -r <original-pcap> -c 100000 -w dataset/201302011400-100000.dump
   ```
   *Note: Ensure the output filename matches `TCPREPLAY_PCAP` in `monitor.py`.*

2. **Build and Setup**:
   ```bash
   make
   sudo sh scripts/veth_setup.sh
   ```

3. **Start Switch**:
   ```bash
   sudo sh scripts/start_switch_grpc.sh
   ```

4. **Listen on the veth3**:
   Veth3 is attached to the output interface of the switch. Using the following command, we can 
verify that packets are being forwarded.
   ```bash
   sudo tcpdump -i veth3
   ```

5. **Run Monitor & Traffic Injection**:
   In a new terminal:
   ```bash
   sudo PATH=$PATH VIRTUAL_ENV=$VIRTUAL_ENV python3 monitor.py
   ```

## References
- Bimodal distribution fitting logic adapted from [university-archive](https://github.com/alarmfox/university-archive).
