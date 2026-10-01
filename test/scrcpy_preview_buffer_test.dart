import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/services/scrcpy_preview_buffer.dart';
import 'package:openpelo/services/scrcpy_protocol.dart';

ScrcpyVideoPacket frame(
  int timestamp, {
  bool key = false,
  bool config = false,
}) => ScrcpyVideoPacket(
  bytes: Uint8List(10),
  timestampUs: timestamp,
  isKeyFrame: key,
  isConfig: config,
);

void main() {
  test('late viewer receives keyframe and every dependent frame in order', () {
    final buffer = ScrcpyPreviewBuffer();
    buffer.add(frame(0, config: true));
    buffer.add(frame(1)); // Cannot decode a partial GOP.
    expect(buffer.packets, isEmpty);
    final key = frame(2, key: true);
    final delta = frame(3);
    buffer.add(key);
    buffer.add(delta);
    expect(buffer.packets, [key, delta]);
    final nextKey = frame(4, key: true);
    buffer.add(nextKey);
    expect(buffer.packets, [nextKey]);
  });

  test('codec change discards frames encoded with the old configuration', () {
    final buffer = ScrcpyPreviewBuffer();
    buffer.add(frame(1, key: true));
    buffer.add(frame(0, config: true));
    buffer.add(frame(2));
    expect(buffer.packets, isEmpty);
    final key = frame(3, key: true);
    buffer.add(key);
    expect(buffer.packets, [key]);
  });

  test('overflow drops the whole GOP and recovers at the next keyframe', () {
    final buffer = ScrcpyPreviewBuffer(maxBytes: 20);
    buffer.add(frame(1, key: true));
    buffer.add(frame(2));
    expect(buffer.packets.length, 2);
    buffer.add(frame(3));
    buffer.add(frame(4));
    expect(buffer.packets, isEmpty);
    final key = frame(5, key: true);
    buffer.add(key);
    expect(buffer.packets, [key]);
  });
}
