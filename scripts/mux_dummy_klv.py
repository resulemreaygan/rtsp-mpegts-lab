#!/usr/bin/env python3
# Copyright (c) 2026 Resul Emre AYGAN
"""Inject dummy KLV PES packets into an MPEG-TS file.

Adds (or replaces) an elementary stream on PID 0x101 using stream type 0x06
and a KLVA registration descriptor. That mapping is what MediaMTX /
mediacommon treat as asynchronous KLV. The KLV bytes are written as real
PES packets (stream_id 0xBD), not only advertised in the PMT.

:license: MIT
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

TS_PACKET = 188
KLV_PID = 0x101
NULL_PID = 0x1FFF
STREAM_TYPE_PRIVATE = 0x06
STREAM_ID_PRIVATE = 0xBD
KLVA = b"KLVA"


def crc32_mpeg2(data: bytes) -> int:
    """Return the MPEG-2 CRC-32 of *data* (PSI tables).

    :param data: Bytes covered by the CRC (section without the CRC field).
    :type data: bytes
    :returns: CRC-32 as an unsigned 32-bit integer.
    :rtype: int
    """
    crc = 0xFFFFFFFF
    for byte in data:
        crc ^= byte << 24
        for _ in range(8):
            if crc & 0x80000000:
                crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF
            else:
                crc = (crc << 1) & 0xFFFFFFFF
    return crc


def ts_pid(packet: bytes) -> int:
    """Return the 13-bit PID of a 188-byte TS packet.

    :param packet: One MPEG-TS packet.
    :type packet: bytes
    :returns: Packet identifier.
    :rtype: int
    """
    return ((packet[1] & 0x1F) << 8) | packet[2]


def ts_payload(packet: bytes) -> bytes:
    """Return the payload of a TS packet (empty if adaptation-only).

    :param packet: One MPEG-TS packet.
    :type packet: bytes
    :returns: Payload bytes.
    :rtype: bytes
    """
    afc = (packet[3] >> 4) & 0x03
    offset = 4
    if afc in (2, 3):
        offset += 1 + packet[4]
    if afc in (1, 3) and offset < TS_PACKET:
        return packet[offset:]
    return b""


def replace_payload(packet: bytes, payload: bytes) -> bytes:
    """Return a copy of *packet* with its payload replaced.

    :param packet: Original 188-byte packet.
    :type packet: bytes
    :param payload: New payload (same length as the original payload).
    :type payload: bytes
    :returns: Updated packet.
    :rtype: bytes
    :raises ValueError: If payload length does not match.
    """
    afc = (packet[3] >> 4) & 0x03
    offset = 4
    if afc in (2, 3):
        offset += 1 + packet[4]
    if len(payload) != TS_PACKET - offset:
        raise ValueError("payload length mismatch")
    return packet[:offset] + payload


def split_packets(data: bytes) -> list[bytes]:
    """Split a TS byte stream into 188-byte packets.

    :param data: Concatenated MPEG-TS.
    :type data: bytes
    :returns: List of packets (trailing incomplete bytes are dropped).
    :rtype: list[bytes]
    """
    n = len(data) // TS_PACKET
    return [data[i * TS_PACKET : (i + 1) * TS_PACKET] for i in range(n)]


def psi_section(payload: bytes) -> bytes:
    """Extract a complete PSI section from a pointer-prefixed payload.

    :param payload: TS payload starting with a pointer_field.
    :type payload: bytes
    :returns: Section bytes including CRC.
    :rtype: bytes
    :raises ValueError: If the section is truncated.
    """
    pointer = payload[0]
    section = payload[1 + pointer :]
    if len(section) < 3:
        raise ValueError("truncated PSI section")
    length = ((section[1] & 0x0F) << 8) | section[2]
    total = 3 + length
    if len(section) < total:
        raise ValueError("PSI section spans multiple packets (unsupported)")
    return section[:total]


def pmt_pid_from_pat(section: bytes) -> int:
    """Return the first program's PMT PID from a PAT section.

    :param section: PAT section including CRC.
    :type section: bytes
    :returns: PMT PID.
    :rtype: int
    :raises ValueError: If PAT has no program map.
    """
    pos = 8
    end = len(section) - 4
    while pos + 4 <= end:
        program = int.from_bytes(section[pos : pos + 2], "big")
        pid = int.from_bytes(section[pos + 2 : pos + 4], "big") & 0x1FFF
        if program != 0:
            return pid
        pos += 4
    raise ValueError("PAT has no program map PID")


def klv_es_entry(pid: int = KLV_PID) -> bytes:
    """Build a PMT ES loop entry for asynchronous KLV.

    :param pid: Elementary PID for KLV.
    :type pid: int
    :returns: Packed PMT elementary-stream bytes.
    :rtype: bytes
    """
    desc = bytes([0x05, 0x04]) + KLVA
    es_info_len = len(desc)
    return bytes(
        [
            STREAM_TYPE_PRIVATE,
            0xE0 | ((pid >> 8) & 0x1F),
            pid & 0xFF,
            0xF0 | ((es_info_len >> 8) & 0x0F),
            es_info_len & 0xFF,
        ]
    ) + desc


def rebuild_pmt_section(section: bytes, klv_pid: int = KLV_PID) -> bytes:
    """Return a PMT section with a KLVA private-data ES on *klv_pid*.

    Existing entries for *klv_pid* are removed, then a 0x06 + KLVA entry
    is appended.

    :param section: Original PMT section including CRC.
    :type section: bytes
    :param klv_pid: PID to advertise as KLV.
    :type klv_pid: int
    :returns: New PMT section with updated length and CRC.
    :rtype: bytes
    """
    program_info_len = ((section[10] & 0x0F) << 8) | section[11]
    es_start = 12 + program_info_len
    es_end = len(section) - 4
    kept = bytearray()
    pos = es_start
    while pos + 5 <= es_end:
        es_pid = ((section[pos + 1] & 0x1F) << 8) | section[pos + 2]
        info_len = ((section[pos + 3] & 0x0F) << 8) | section[pos + 4]
        entry_len = 5 + info_len
        if es_pid != klv_pid:
            kept.extend(section[pos : pos + entry_len])
        pos += entry_len
    new_es = bytes(kept) + klv_es_entry(klv_pid)
    head = bytearray(section[:es_start])
    body = bytes(head) + new_es
    section_length = len(body) + 4 - 3
    body = bytearray(body)
    body[1] = (body[1] & 0xF0) | ((section_length >> 8) & 0x0F)
    body[2] = section_length & 0xFF
    crc = crc32_mpeg2(bytes(body))
    return bytes(body) + crc.to_bytes(4, "big")


def patch_pmt_payload(payload: bytes, new_section: bytes) -> bytes:
    """Replace the PSI section inside a PMT payload, keeping pointer stuffing.

    :param payload: Original TS payload.
    :type payload: bytes
    :param new_section: Replacement PMT section.
    :type new_section: bytes
    :returns: Payload padded with 0xFF to the original length.
    :rtype: bytes
    :raises ValueError: If the new section does not fit.
    """
    pointer = payload[0]
    prefix = payload[: 1 + pointer]
    new_payload = prefix + new_section
    if len(new_payload) > len(payload):
        raise ValueError("new PMT section does not fit in the original packet")
    return new_payload + b"\xff" * (len(payload) - len(new_payload))


def make_pes(payload: bytes) -> bytes:
    """Build a private-stream-1 PES packet (no PTS) around *payload*.

    :param payload: KLV unit bytes.
    :type payload: bytes
    :returns: PES packet.
    :rtype: bytes
    """
    optional = bytes([0x80, 0x00, 0x00])
    length = len(optional) + len(payload)
    return bytes(
        [0x00, 0x00, 0x01, STREAM_ID_PRIVATE, (length >> 8) & 0xFF, length & 0xFF]
    ) + optional + payload


def make_ts_packet(pid: int, pes: bytes, continuity: int) -> bytes:
    """Pack a short PES into one TS packet with adaptation stuffing.

    :param pid: Packet identifier.
    :type pid: int
    :param pes: PES bytes (must fit in one packet).
    :type pes: bytes
    :param continuity: Continuity counter (0-15).
    :type continuity: int
    :returns: 188-byte TS packet.
    :rtype: bytes
    :raises ValueError: If *pes* is too large for one packet.
    """
    # 4 header + 1 adaptation_length + 1 flags + stuffing + payload = 188
    stuffing = 188 - 4 - 2 - len(pes)
    if stuffing < 0:
        raise ValueError(f"PES too large for one TS packet ({len(pes)} bytes)")
    header = bytes(
        [
            0x47,
            0x40 | ((pid >> 8) & 0x1F),  # PUSI
            pid & 0xFF,
            0x30 | (continuity & 0x0F),  # adaptation + payload
        ]
    )
    adaptation = bytes([1 + stuffing, 0x40]) + (b"\xff" * stuffing)
    return header + adaptation + pes


def inject(
    ts_bytes: bytes,
    klv: bytes,
    count: int,
    klv_pid: int = KLV_PID,
) -> bytes:
    """Return a TS with KLV advertised in the PMT and *count* PES units.

    :param ts_bytes: Input MPEG-TS.
    :type ts_bytes: bytes
    :param klv: Dummy KLV unit.
    :type klv: bytes
    :param count: Number of KLV PES packets to write.
    :type count: int
    :param klv_pid: Elementary PID for KLV.
    :type klv_pid: int
    :returns: Output MPEG-TS.
    :rtype: bytes
    """
    packets = split_packets(ts_bytes)
    if not packets:
        raise ValueError("input is not a MPEG-TS")

    pat_payload = None
    for packet in packets:
        if ts_pid(packet) == 0 and (packet[1] >> 6) & 1:
            pat_payload = ts_payload(packet)
            break
    if not pat_payload:
        raise ValueError("PAT not found")
    pmt_pid = pmt_pid_from_pat(psi_section(pat_payload))

    pmt_section = None
    for packet in packets:
        if ts_pid(packet) == pmt_pid and (packet[1] >> 6) & 1:
            pmt_section = rebuild_pmt_section(psi_section(ts_payload(packet)), klv_pid)
            break
    if pmt_section is None:
        raise ValueError("PMT not found")

    patched: list[bytes] = []
    for packet in packets:
        pid = ts_pid(packet)
        if pid == klv_pid:
            continue
        if pid == pmt_pid and (packet[1] >> 6) & 1:
            packet = replace_payload(
                packet, patch_pmt_payload(ts_payload(packet), pmt_section)
            )
        patched.append(packet)

    pes = make_pes(klv)
    extras = [make_ts_packet(klv_pid, pes, i & 0x0F) for i in range(count)]
    out: list[bytes] = []
    for packet in patched:
        if extras and ts_pid(packet) == NULL_PID:
            out.append(extras.pop(0))
        else:
            out.append(packet)
    if extras:
        stride = max(1, len(out) // (len(extras) + 1))
        merged: list[bytes] = []
        ei = 0
        for i, packet in enumerate(out):
            merged.append(packet)
            if ei < len(extras) and (i + 1) % stride == 0:
                merged.append(extras[ei])
                ei += 1
        merged.extend(extras[ei:])
        out = merged
    return b"".join(out)


def main() -> int:
    """CLI: mux dummy KLV PES packets into an MPEG-TS file.

    :returns: Process exit code.
    :rtype: int
    """
    parser = argparse.ArgumentParser(
        description="Inject dummy KLV PES packets into an MPEG-TS file.",
    )
    parser.add_argument("input_ts", type=Path, help="Video MPEG-TS")
    parser.add_argument("klv", type=Path, help="Raw KLV unit (e.g. dummy.klv)")
    parser.add_argument("output_ts", type=Path, help="Output MPEG-TS")
    parser.add_argument(
        "--count",
        type=int,
        default=50,
        help="Number of KLV PES packets to write (default: 50)",
    )
    args = parser.parse_args()

    ts_bytes = args.input_ts.read_bytes()
    klv = args.klv.read_bytes()
    if not klv:
        print("ERROR: KLV file is empty", file=sys.stderr)
        return 1
    if args.count < 1:
        print("ERROR: --count must be >= 1", file=sys.stderr)
        return 1

    out = inject(ts_bytes, klv, args.count)
    args.output_ts.write_bytes(out)

    n101 = sum(
        1
        for i in range(len(out) // TS_PACKET)
        if ts_pid(out[i * TS_PACKET : (i + 1) * TS_PACKET]) == KLV_PID
    )
    print(
        f"wrote {args.output_ts} ({len(out)} bytes, pid 0x{KLV_PID:x} packets={n101})",
        flush=True,
    )
    if n101 < 1:
        print("ERROR: no KLV packets in output", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
