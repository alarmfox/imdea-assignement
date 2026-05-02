/*
 * File heavily inspired from https://github.com/jafingerhut/p4-guide/blob/master/demo1/demo1.p4_16.p4
 *
 * This p4 program simply takes traffic from port 0 and forwards on port 1.
 *
 * Regarding feature extraction, I collect flows and packet size in registry and communicate through
 * the control plane in Python.
 *
 */

#include <core.p4>
#include <v1model.p4>

/*
 * Standard data structures.
 */
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

header tcp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset;
    bit<3>  res;
    bit<9>  flags;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
}

header udp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<16> length_;
    bit<16> checksum;
}

/* No metadata needed */
struct metadata_t {}

struct headers_t {
    ethernet_t ethernet;
    ipv4_t     ipv4;
    tcp_t      tcp;
    udp_t      udp;
}

parser parserImpl(packet_in packet,
                  out headers_t hdr,
                  inout metadata_t meta,
                  inout standard_metadata_t stdmeta)
{
    const bit<16> ETHERTYPE_IPV4 = 16w0x0800;

    state start {
        transition parse_ethernet;
    }
    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            ETHERTYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }
    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            8w6: parse_tcp;
            8w17: parse_udp;
            default: accept;
        }
    }
    state parse_tcp { packet.extract(hdr.tcp); transition accept; }
    state parse_udp { packet.extract(hdr.udp); transition accept; }
}


/*
 * Extract features and forward to the output port.
 */
control ingressImpl(inout headers_t hdr,
                    inout metadata_t meta,
                    inout standard_metadata_t stdmeta)
{
    /*
     * Feature 1: Packet Size Histogram
     *
     * Using a counter instead of a register avoids encoding metadata in a custom header.
     * This is possible assuming that this counter will have a limited number of entries. This
     * is true since packet size is limited by the MTU (max 1500), as I analyzed in the PCAP
     */
    counter(2048, CounterType.packets) pkt_size_hist;

    /*
     * Feature 2: Flow duration tracker
     *
     * I use the flow_tracker to count the number of flows (and other metadata).
     *
     * For each flow, I record the start time, the last timestamp and the protocol (in 3 registers)
     */
    counter(65536, CounterType.packets_and_bytes) flow_tracker;
    register<bit<48>>(65536) flow_start_ts;
    register<bit<48>>(65536) flow_last_ts;
    register<bit<8>>(65536) flow_proto;

    apply {
        if (hdr.ipv4.isValid()) {

            /*
             * Extract the packet size. Since packets are truncated, I cannot leverage the metadata,
             * but i need to lock into the ipv4 header and add the size of the ethernet header
             */
            bit<32> p_size = (bit<32>)hdr.ipv4.totalLen + 14;
            pkt_size_hist.count(p_size);

            // 2. Safely extract ports for hashing
            bit<16> s_port = 0;
            bit<16> d_port = 0;

            if (hdr.tcp.isValid()) {
                s_port = hdr.tcp.srcPort;
                d_port = hdr.tcp.dstPort;
            } else if (hdr.udp.isValid()) {
                s_port = hdr.udp.srcPort;
                d_port = hdr.udp.dstPort;
            }

            /* Compute the flow ID using the 5-tuple */
            bit<32> flow_idx;
            hash(flow_idx, HashAlgorithm.crc16, (bit<32>)0, {
                hdr.ipv4.srcAddr, hdr.ipv4.dstAddr, hdr.ipv4.protocol, s_port, d_port
            }, (bit<32>)65535);

            /* Count the flow */
            flow_tracker.count(flow_idx);
            flow_proto.write(flow_idx, hdr.ipv4.protocol);

            /* Update durations registers to track duration */
            bit<48> current_ts = stdmeta.ingress_global_timestamp;
            bit<48> first_ts;

            // Read the start timestamp for this flow index
            flow_start_ts.read(first_ts, flow_idx);

            // If it's 0, this is the first packet of the flow
            if (first_ts == 0) {
                flow_start_ts.write(flow_idx, current_ts);
            }

            // Always update the 'last seen' timestamp
            flow_last_ts.write(flow_idx, current_ts);
        }

        // Blind forward to Port 1
        stdmeta.egress_spec = 1;
    }
}

/*
 * Do nothing for egress
 */
control egressImpl(inout headers_t hdr,
                   inout metadata_t meta,
                   inout standard_metadata_t stdmeta)
{
    apply {
        // No-op
    }
}

control deparserImpl(packet_out packet, in headers_t hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.tcp);
        packet.emit(hdr.udp);
    }
}

control verifyChecksum(inout headers_t hdr, inout metadata_t meta) {
    apply { }
}

control updateChecksum(inout headers_t hdr, inout metadata_t meta) {
    apply { }
}

V1Switch (
    parserImpl(),
    verifyChecksum(),
    ingressImpl(),
    egressImpl(),
    updateChecksum(),
    deparserImpl()
) main;
