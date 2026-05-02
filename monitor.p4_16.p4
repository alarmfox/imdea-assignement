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
// Feature 1: Packet Size Histogram
    counter(2048, CounterType.packets) pkt_size_hist;

    // Feature 2: Flow Tracker (Tracks BOTH packets and bytes)
    counter(65536, CounterType.packets_and_bytes) flow_tracker;

    apply {
        if (hdr.ipv4.isValid()) {

            // 1. Record Packet Size
            bit<32> p_size = (bit<32>)stdmeta.packet_length;
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

            // 3. Hash the 5-tuple
            bit<32> flow_idx;
            hash(flow_idx, HashAlgorithm.crc16, (bit<32>)0, {
                hdr.ipv4.srcAddr, hdr.ipv4.dstAddr, hdr.ipv4.protocol, s_port, d_port
            }, (bit<32>)65535);

            // 4. Record the flow
            flow_tracker.count(flow_idx);
        }

        // Blind forward to Port 1
        stdmeta.egress_spec = 1;
    }}

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
