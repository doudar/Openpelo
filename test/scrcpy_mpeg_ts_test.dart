import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/services/scrcpy_mpeg_ts.dart';
import 'package:openpelo/services/scrcpy_protocol.dart';

void main() {
  test('emits decodable PAT, PMT and timestamped H264 PES', () {
    final muxer = ScrcpyMpegTsMuxer();
    final config = Uint8List.fromList([
      0,
      0,
      0,
      1,
      0x67,
      0x42,
      0,
      0,
      0,
      0,
      1,
      0x68,
      0xce,
    ]);
    expect(
      muxer.mux(
        ScrcpyVideoPacket(
          bytes: config,
          timestampUs: 0,
          isConfig: true,
          isKeyFrame: false,
        ),
      ),
      isEmpty,
    );

    final idr = Uint8List.fromList([
      0,
      0,
      0,
      1,
      0x65,
      ...List<int>.filled(500, 0xaa),
    ]);
    final output = muxer.mux(
      ScrcpyVideoPacket(
        bytes: idr,
        timestampUs: 5000000,
        isConfig: false,
        isKeyFrame: true,
      ),
    );
    expect(output.length % 188, 0);
    final packets = _packets(output);
    expect(_pid(packets[0]), 0);
    expect(_pid(packets[1]), ScrcpyMpegTsMuxer.pmtPid);
    expect(_pid(packets[2]), ScrcpyMpegTsMuxer.videoPid);
    expect(packets.every((p) => p[0] == 0x47), true);
    expect(_crcRemainder(_section(packets[0])), 0);
    expect(_crcRemainder(_section(packets[1])), 0);
    expect(_section(packets[1])[12], 0x1b); // H.264 stream type

    final firstVideo = packets[2];
    expect(firstVideo[1] & 0x40, 0x40); // PES payload start
    expect(firstVideo[5] & 0x10, 0x10); // PCR present
    expect(_readPcrBase(firstVideo, 6), 90000);
    final pesOffset = 5 + firstVideo[4];
    expect(firstVideo.sublist(pesOffset, pesOffset + 4), [0, 0, 1, 0xe0]);
    expect(_readPts(firstVideo, pesOffset + 9), 90000);
    expect(firstVideo.sublist(pesOffset + 14, pesOffset + 20), [
      0,
      0,
      0,
      1,
      9,
      0xf0,
    ]); // AUD
    expect(
      firstVideo.sublist(pesOffset + 20, pesOffset + 27),
      config.sublist(0, 7),
    ); // SPS before IDR
  });

  test('continues video continuity and repeats tables for IDRs', () {
    final muxer = ScrcpyMpegTsMuxer();
    ScrcpyVideoPacket frame(int us, bool key) => ScrcpyVideoPacket(
      bytes: Uint8List.fromList([0, 0, 0, 1, key ? 0x65 : 0x41, 1]),
      timestampUs: us,
      isConfig: false,
      isKeyFrame: key,
    );
    final first = _packets(muxer.mux(frame(123456, true)));
    final second = _packets(muxer.mux(frame(156789, false)));
    final third = _packets(muxer.mux(frame(190000, true)));
    expect(_pid(second.first), ScrcpyMpegTsMuxer.videoPid);
    expect(_pid(third[0]), 0);
    expect(_pid(third[1]), ScrcpyMpegTsMuxer.pmtPid);
    expect(third[0][3] & 15, 1); // PAT continuity
    expect(third[1][3] & 15, 1); // PMT continuity
    expect(second[0][3] & 15, (first.last[3] + 1) & 15);
    expect(_readPcrBase(second.first, 6), greaterThan(90000));
  });
}

List<Uint8List> _packets(Uint8List bytes) => [
  for (var offset = 0; offset < bytes.length; offset += 188)
    Uint8List.sublistView(bytes, offset, offset + 188),
];

int _pid(Uint8List packet) => ((packet[1] & 0x1f) << 8) | packet[2];

Uint8List _section(Uint8List packet) {
  final start = 5 + packet[4]; // pointer_field
  final length = 3 + (((packet[start + 1] & 0x0f) << 8) | packet[start + 2]);
  return Uint8List.sublistView(packet, start, start + length);
}

int _crcRemainder(Uint8List section) {
  var crc = 0xffffffff;
  for (final byte in section) {
    crc ^= byte << 24;
    for (var bit = 0; bit < 8; bit++) {
      crc = ((crc & 0x80000000) != 0)
          ? ((crc << 1) ^ 0x04c11db7) & 0xffffffff
          : (crc << 1) & 0xffffffff;
    }
  }
  return crc;
}

int _readPcrBase(Uint8List packet, int offset) =>
    (packet[offset] << 25) |
    (packet[offset + 1] << 17) |
    (packet[offset + 2] << 9) |
    (packet[offset + 3] << 1) |
    (packet[offset + 4] >> 7);

int _readPts(Uint8List packet, int offset) =>
    ((packet[offset] >> 1 & 7) << 30) |
    (packet[offset + 1] << 22) |
    ((packet[offset + 2] >> 1) << 15) |
    (packet[offset + 3] << 7) |
    (packet[offset + 4] >> 1);
