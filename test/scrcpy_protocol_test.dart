import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/services/scrcpy_protocol.dart';

void main() {
  test('decodes v3.3.4 codec and packet headers', () {
    final header = ByteData(12)
      ..setUint32(0, ScrcpyProtocol.codecH264)
      ..setUint32(4, 1280)
      ..setUint32(8, 720);
    final video = ScrcpyProtocol.parseVideoHeader(header.buffer.asUint8List());
    expect(video.width, 1280);
    expect(video.height, 720);

    final config = ByteData(12)
      ..setUint64(0, ScrcpyProtocol.configFlag)
      ..setUint32(8, 22);
    final configPacket = ScrcpyProtocol.parseFrameHeader(
      config.buffer.asUint8List(),
    );
    expect(configPacket.isConfig, true);
    expect(configPacket.timestampUs, 0);

    final key = ByteData(12)
      ..setUint64(0, ScrcpyProtocol.keyFrameFlag | 1234567)
      ..setUint32(8, 4096);
    final keyPacket = ScrcpyProtocol.parseFrameHeader(key.buffer.asUint8List());
    expect(keyPacket.isKeyFrame, true);
    expect(keyPacket.timestampUs, 1234567);
    expect(keyPacket.size, 4096);
  });

  test('rejects impossible video packet allocations', () {
    final header = ByteData(12)
      ..setUint64(0, 1)
      ..setUint32(8, ScrcpyProtocol.maxPacketSize + 1);
    expect(
      () => ScrcpyProtocol.parseFrameHeader(header.buffer.asUint8List()),
      throwsFormatException,
    );
  });

  test('writes exact v3.3.4 control layouts', () {
    final key = ScrcpyProtocol.keycode(keycode: 4, action: 0);
    expect(key.length, 14);
    expect(key[0], 0);
    expect(ByteData.sublistView(key).getUint32(2), 4);

    final touch = ScrcpyProtocol.touch(
      action: 0,
      x: 100,
      y: 200,
      width: 1280,
      height: 720,
    );
    final data = ByteData.sublistView(touch);
    expect(touch.length, 32);
    expect(data.getUint64(2), 0xfffffffffffffffe);
    expect(data.getInt32(10), 100);
    expect(data.getInt32(14), 200);
    expect(data.getUint16(18), 1280);
    expect(data.getUint16(20), 720);

    final scroll = ScrcpyProtocol.scroll(
      x: 1,
      y: 2,
      width: 1280,
      height: 720,
      vertical: 1,
    );
    expect(scroll.length, 21);
    expect(ByteData.sublistView(scroll).getInt16(15), 2048);
    final saturated = ScrcpyProtocol.scroll(
      x: 1,
      y: 2,
      width: 1280,
      height: 720,
      horizontal: -16,
      vertical: 16,
    );
    expect(ByteData.sublistView(saturated).getInt16(13), -32768);
    expect(ByteData.sublistView(saturated).getInt16(15), 32767);

    final text = ScrcpyProtocol.text('Peloton');
    expect(text[0], 1);
    expect(ByteData.sublistView(text).getUint32(1), 7);
  });
}
