import 'dart:typed_data';

import 'scrcpy_protocol.dart';

/// Minimal live MPEG-TS muxer for scrcpy's Annex B H.264 access units.
/// Each instance belongs to one preview client so continuity counters and
/// timestamps start afresh on reconnect. Recording uses the original packets.
class ScrcpyMpegTsMuxer {
  static const int packetSize = 188;
  static const int pmtPid = 0x1000;
  static const int videoPid = 0x0100;
  static const int _ptsMask = (1 << 33) - 1;
  static const List<int> _aud = [0, 0, 0, 1, 9, 0xf0];

  final Map<int, int> _continuity = {};
  Uint8List? _config;
  int? _firstTimestampUs;

  void addConfig(Uint8List bytes) => _config = Uint8List.fromList(bytes);

  /// Returns one contiguous TS chunk per encoded access unit. Config packets
  /// are held and prepended to the next IDR, so a new viewer can decode.
  Uint8List mux(ScrcpyVideoPacket packet) {
    if (packet.isConfig) {
      addConfig(packet.bytes);
      return Uint8List(0);
    }
    _firstTimestampUs ??= packet.timestampUs;
    final elapsedUs = packet.timestampUs - _firstTimestampUs!;
    if (elapsedUs < 0) {
      throw const FormatException('scrcpy timestamps moved backward');
    }
    final pts90k = (90000 + elapsedUs * 90 ~/ 1000) & _ptsMask;
    final bytes = BytesBuilder(copy: false);
    if (packet.isKeyFrame) {
      bytes.add(_psiPacket(0, _patSection()));
      bytes.add(_psiPacket(pmtPid, _pmtSection()));
    }
    final accessUnit = BytesBuilder(copy: false)..add(_aud);
    if (packet.isKeyFrame && _config != null) accessUnit.add(_config!);
    accessUnit.add(packet.bytes);
    final payload = accessUnit.takeBytes();
    // Video PES_packet_length is zero: H.264 access units can exceed 64 KiB.
    final pes = Uint8List(14 + payload.length);
    pes.setRange(0, 9, const [0, 0, 1, 0xe0, 0, 0, 0x80, 0x80, 5]);
    _writePts(pes, 9, pts90k);
    pes.setRange(14, pes.length, payload);
    _packetizePes(bytes, pes, pts90k);
    return bytes.takeBytes();
  }

  Uint8List _psiPacket(int pid, Uint8List section) {
    final packet = Uint8List(packetSize);
    packet.fillRange(0, packet.length, 0xff);
    _writeHeader(packet, pid, true, 1);
    packet[4] = 0; // pointer_field
    packet.setRange(5, 5 + section.length, section);
    return packet;
  }

  Uint8List _patSection() {
    final section = Uint8List.fromList([
      0x00, 0xb0, 0x0d, // PAT and section length 13
      0x00, 0x01, 0xc1, 0x00, 0x00, // TS id, version, section indices
      0x00, 0x01, // program number
      0xf0 | (pmtPid >> 8), pmtPid & 0xff,
      0, 0, 0, 0,
    ]);
    _writeCrc(section);
    return section;
  }

  Uint8List _pmtSection() {
    final section = Uint8List.fromList([
      0x02, 0xb0, 0x12, // PMT and section length 18
      0x00, 0x01, 0xc1, 0x00, 0x00, // program, version, section indices
      0xe0 | (videoPid >> 8), videoPid & 0xff, // PCR PID
      0xf0, 0x00, // no program descriptors
      0x1b, // H.264 stream type
      0xe0 | (videoPid >> 8), videoPid & 0xff,
      0xf0, 0x00, // no ES descriptors
      0, 0, 0, 0,
    ]);
    _writeCrc(section);
    return section;
  }

  void _writeCrc(Uint8List section) {
    var crc = 0xffffffff;
    for (var i = 0; i < section.length - 4; i++) {
      crc ^= section[i] << 24;
      for (var bit = 0; bit < 8; bit++) {
        crc = ((crc & 0x80000000) != 0)
            ? ((crc << 1) ^ 0x04c11db7) & 0xffffffff
            : (crc << 1) & 0xffffffff;
      }
    }
    final offset = section.length - 4;
    section[offset] = crc >> 24;
    section[offset + 1] = crc >> 16;
    section[offset + 2] = crc >> 8;
    section[offset + 3] = crc;
  }

  void _packetizePes(BytesBuilder output, Uint8List pes, int pts90k) {
    var offset = 0;
    var first = true;
    while (offset < pes.length) {
      final remaining = pes.length - offset;
      final capacity = first ? 176 : 184;
      final payloadLength = remaining < capacity ? remaining : capacity;
      final adaptation = first || payloadLength < 184;
      final packet = Uint8List(packetSize);
      packet.fillRange(0, packet.length, 0xff);
      _writeHeader(packet, videoPid, first, adaptation ? 3 : 1);
      int payloadOffset;
      if (adaptation) {
        final adaptationLength = 183 - payloadLength;
        packet[4] = adaptationLength;
        if (adaptationLength > 0) {
          packet[5] = first ? 0x10 : 0;
          if (first) _writePcr(packet, 6, pts90k);
        }
        payloadOffset = 5 + adaptationLength;
      } else {
        payloadOffset = 4;
      }
      packet.setRange(payloadOffset, packetSize, pes, offset);
      output.add(packet);
      offset += payloadLength;
      first = false;
    }
  }

  void _writeHeader(
    Uint8List packet,
    int pid,
    bool payloadStart,
    int adaptationControl,
  ) {
    packet[0] = 0x47;
    packet[1] = (payloadStart ? 0x40 : 0) | ((pid >> 8) & 0x1f);
    packet[2] = pid & 0xff;
    final counter = _continuity[pid] ?? 0;
    packet[3] = (adaptationControl << 4) | counter;
    _continuity[pid] = (counter + 1) & 0x0f;
  }

  static void _writePts(Uint8List out, int offset, int value) {
    out[offset] = 0x20 | (((value >> 30) & 0x07) << 1) | 1;
    out[offset + 1] = (value >> 22) & 0xff;
    out[offset + 2] = (((value >> 15) & 0x7f) << 1) | 1;
    out[offset + 3] = (value >> 7) & 0xff;
    out[offset + 4] = ((value & 0x7f) << 1) | 1;
  }

  static void _writePcr(Uint8List out, int offset, int base) {
    out[offset] = (base >> 25) & 0xff;
    out[offset + 1] = (base >> 17) & 0xff;
    out[offset + 2] = (base >> 9) & 0xff;
    out[offset + 3] = (base >> 1) & 0xff;
    out[offset + 4] = ((base & 1) << 7) | 0x7e;
    out[offset + 5] = 0; // PCR extension 0
  }
}
