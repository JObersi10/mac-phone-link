#!/usr/bin/env python3
"""parse_transport.py — extract ONLY protocol structure from a pktmon pcapng.

Reads a (truncated) pcapng from the Phone Link transport capture and prints:
  - a flow table (5-tuple, packet count, byte totals, min/max payload length)
  - every STUN/TURN message it sees, decoded to message-type + attribute-type
    names, plus any XOR-MAPPED-ADDRESS (the ICE candidate address)

It never prints media payload. RTP/media packets are summarized as flows only;
their bytes are counted but not dumped. STUN is detected by the RFC 5389 magic
cookie (0x2112A442) at offset 4 of the UDP payload.

Pure stdlib, no deps. Usage:
    python3 -I scripts/parse_transport.py "<path to transport.pcapng>"
"""
import struct
import sys
import socket

STUN_MAGIC = 0x2112A442

STUN_METHODS = {0x0001: "Binding", 0x0003: "Allocate", 0x0004: "Refresh",
                0x0006: "Send", 0x0007: "Data", 0x0008: "CreatePermission",
                0x0009: "ChannelBind"}
STUN_CLASSES = {0x0000: "Request", 0x0010: "Indication",
                0x0100: "Success", 0x0110: "Error"}
STUN_ATTRS = {0x0001: "MAPPED-ADDRESS", 0x0006: "USERNAME",
              0x0008: "MESSAGE-INTEGRITY", 0x0009: "ERROR-CODE",
              0x000A: "UNKNOWN-ATTRIBUTES", 0x000C: "CHANNEL-NUMBER",
              0x000D: "LIFETIME", 0x0012: "XOR-PEER-ADDRESS",
              0x0013: "DATA", 0x0014: "REALM", 0x0015: "NONCE",
              0x0016: "XOR-RELAYED-ADDRESS", 0x0019: "REQUESTED-TRANSPORT",
              0x0020: "XOR-MAPPED-ADDRESS", 0x0024: "PRIORITY",
              0x0025: "USE-CANDIDATE",
              0x8022: "SOFTWARE", 0x8023: "ALTERNATE-SERVER",
              0x8028: "FINGERPRINT", 0x8029: "ICE-CONTROLLED",
              0x802A: "ICE-CONTROLLING", 0x8070: "IMPLEMENTATION-VERSION"}


def read_blocks(data):
    """Yield (block_type, body) from a pcapng; handles byte order from SHB."""
    off = 0
    endian = "<"
    n = len(data)
    while off + 8 <= n:
        bt = struct.unpack_from(endian + "I", data, off)[0]
        if bt == 0x0A0D0D0A:  # Section Header Block — read its magic for order
            bom = struct.unpack_from("<I", data, off + 8)[0]
            endian = "<" if bom == 0x1A2B3C4D else ">"
        blen = struct.unpack_from(endian + "I", data, off + 4)[0]
        if blen < 12 or off + blen > n:
            break
        yield bt, data[off + 8: off + blen - 4], endian
        off += blen


def parse_stun(p):
    """Return a short dict for a STUN message, or None."""
    if len(p) < 20:
        return None
    mtype, mlen, cookie = struct.unpack_from(">HHI", p, 0)
    if cookie != STUN_MAGIC:
        return None
    method = (mtype & 0x000F) | ((mtype & 0x00E0) >> 1) | ((mtype & 0x3E00) >> 2)
    cls = (mtype & 0x0100) | (mtype & 0x0010)
    attrs = []
    xor_addrs = []
    o = 20
    end = min(20 + mlen, len(p))
    while o + 4 <= end:
        atype, alen = struct.unpack_from(">HH", p, o)
        name = STUN_ATTRS.get(atype, f"0x{atype:04X}")
        attrs.append(name)
        if atype in (0x0020, 0x0016, 0x0012) and o + 4 + alen <= len(p) and alen >= 8:
            fam = p[o + 5]
            xport = struct.unpack_from(">H", p, o + 6)[0] ^ (STUN_MAGIC >> 16)
            if fam == 0x01:
                raw = struct.unpack_from(">I", p, o + 8)[0] ^ STUN_MAGIC
                ip = socket.inet_ntoa(struct.pack(">I", raw))
                xor_addrs.append(f"{name}={ip}:{xport}")
        o += 4 + alen + ((4 - alen % 4) % 4)
    return {"method": STUN_METHODS.get(method, f"0x{method:04X}"),
            "class": STUN_CLASSES.get(cls, f"0x{cls:04X}"),
            "attrs": attrs, "xor": xor_addrs}


def ip_udp_tcp(pkt):
    """Strip link layer, return (proto, src, dst, sport, dport, payload)."""
    # Try Ethernet first; fall back to raw IPv4/IPv6 by version nibble.
    for base in (14, 0):
        if base == 14 and len(pkt) < 14:
            continue
        b = pkt[base:]
        if not b:
            continue
        ver = b[0] >> 4
        if ver == 4 and len(b) >= 20:
            ihl = (b[0] & 0x0F) * 4
            proto = b[9]
            src = socket.inet_ntoa(b[12:16])
            dst = socket.inet_ntoa(b[16:20])
            l4 = b[ihl:]
            break
        elif ver == 6 and len(b) >= 40:
            proto = b[6]
            src = socket.inet_ntop(socket.AF_INET6, b[8:24])
            dst = socket.inet_ntop(socket.AF_INET6, b[24:40])
            l4 = b[40:]
            break
    else:
        return None
    if proto == 17 and len(l4) >= 8:   # UDP
        sport, dport = struct.unpack_from(">HH", l4, 0)
        return ("udp", src, dst, sport, dport, l4[8:])
    if proto == 6 and len(l4) >= 20:   # TCP
        sport, dport = struct.unpack_from(">HH", l4, 0)
        off = (l4[12] >> 4) * 4
        return ("tcp", src, dst, sport, dport, l4[off:])
    return None


def main():
    if len(sys.argv) < 2:
        print("usage: parse_transport.py <file.pcapng>")
        return 1
    with open(sys.argv[1], "rb") as fh:
        data = fh.read()
    flows = {}
    stun_seen = {}
    xor_all = set()
    npkts = 0
    for bt, body, endian in read_blocks(data):
        if bt != 0x00000006:  # Enhanced Packet Block only
            continue
        if len(body) < 20:
            continue
        caplen = struct.unpack_from(endian + "I", body, 12)[0]
        pkt = body[20:20 + caplen]
        parsed = ip_udp_tcp(pkt)
        if not parsed:
            continue
        npkts += 1
        proto, src, dst, sport, dport, payload = parsed
        key = (proto, src, sport, dst, dport)
        f = flows.setdefault(key, [0, 0, 1 << 30, 0])
        f[0] += 1
        f[1] += len(payload)
        f[2] = min(f[2], len(payload))
        f[3] = max(f[3], len(payload))
        st = parse_stun(payload)
        if st:
            tag = f"{st['class']} {st['method']}"
            stun_seen[tag] = stun_seen.get(tag, 0) + 1
            for x in st["xor"]:
                xor_all.add(x)

    print(f"# packets parsed: {npkts}\n")
    print("## flows (proto src:sport -> dst:dport  pkts  bytes  min/max payload)")
    for key, v in sorted(flows.items(), key=lambda kv: -kv[1][0]):
        proto, src, sport, dst, dport = key
        print(f"{proto} {src}:{sport} -> {dst}:{dport}  "
              f"{v[0]}pk {v[1]}B  {v[2]}/{v[3]}")
    print("\n## STUN/TURN messages seen")
    if stun_seen:
        for tag, c in sorted(stun_seen.items(), key=lambda kv: -kv[1]):
            print(f"  {c:5d}  {tag}")
    else:
        print("  (none — no STUN magic cookie found; media may be plain UDP/relay)")
    print("\n## ICE candidate addresses (from XOR-*-ADDRESS attrs)")
    for x in sorted(xor_all):
        print(f"  {x}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
