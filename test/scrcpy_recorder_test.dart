import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/services/scrcpy_recorder.dart';

// Small synthetic Annex B access units exercise muxing rather than decoding.
final config = Uint8List.fromList([
  0,
  0,
  0,
  1,
  ...spsFixture(),
  0,
  0,
  1,
  0x68,
  0xce,
  0x3c,
  0x80,
]);
final idr = Uint8List.fromList([0, 0, 0, 1, 0x65, 0xb8, 0x80]);
final predicted = Uint8List.fromList([0, 0, 1, 0x41, 0xe0, 0x80]);

// Minimal baseline/high-profile SPS syntax with selectable cropping and fields.
// Includes Annex B emulation prevention as an encoder would emit it.
List<int> spsFixture({
  int columns = 80,
  int rows = 45,
  int cropBottom = 0,
  int cropRight = 0,
  bool interlaced = false,
  bool high = false,
  bool scaling = false,
  int pocCycle = 0,
  int pocOffset = 0,
}) {
  final bits = StringBuffer();
  void fixed(int value, int count) =>
      bits.write(value.toRadixString(2).padLeft(count, '0'));
  void ue(int value) {
    final code = (value + 1).toRadixString(2);
    bits.write('0' * (code.length - 1));
    bits.write(code);
  }

  fixed(high ? 100 : 66, 8);
  fixed(0, 8);
  fixed(30, 8);
  ue(0); // SPS id
  if (high) {
    ue(1);
    ue(0);
    ue(0);
    fixed(0, 1);
    fixed(scaling ? 1 : 0, 1);
    if (scaling) {
      for (var i = 0; i < 8; i++) {
        fixed(1, 1);
        for (var j = 0; j < (i < 6 ? 16 : 64); j++) {
          ue(0);
        }
      }
    }
  }
  ue(0); // frame_num bits
  ue(pocCycle == 0 ? 0 : 1);
  if (pocCycle == 0) {
    ue(0);
  } else {
    fixed(0, 1);
    ue(pocOffset == 0 ? 0 : pocOffset * 2 - 1);
    ue(0);
    ue(pocCycle);
    for (var i = 0; i < pocCycle; i++) {
      ue(0);
    }
  }
  ue(1);
  fixed(0, 1); // references, gaps
  ue(columns - 1);
  ue(rows - 1);
  fixed(interlaced ? 0 : 1, 1);
  if (interlaced) fixed(0, 1);
  fixed(1, 1); // direct inference
  fixed(cropBottom != 0 || cropRight != 0 ? 1 : 0, 1);
  if (cropBottom != 0 || cropRight != 0) {
    ue(0);
    ue(cropRight);
    ue(0);
    ue(cropBottom);
  }
  fixed(0, 1); // no VUI
  fixed(1, 1); // rbsp_stop_one_bit
  while (bits.length % 8 != 0) {
    fixed(0, 1);
  }
  final raw = bits.toString();
  final result = <int>[0x67];
  var zeros = 0;
  for (var i = 0; i < raw.length; i += 8) {
    final byte = int.parse(raw.substring(i, i + 8), radix: 2);
    if (zeros >= 2 && byte <= 3) {
      result.add(3);
      zeros = 0;
    }
    result.add(byte);
    zeros = byte == 0 ? zeros + 1 : 0;
  }
  return result;
}

int u32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint32(offset);
int box(Uint8List bytes, String name) {
  for (var i = 4; i <= bytes.length - 4; i++) {
    if (String.fromCharCodes(bytes.sublist(i, i + 4)) == name) return i - 4;
  }
  throw StateError('Missing $name');
}

void main() {
  late Directory temp;
  late String path;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('openpelo-recording-test-');
    path = '${temp.path}${Platform.pathSeparator}tutorial.mp4';
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<ScrcpyRecorder> start() => ScrcpyRecorder.start(
    path: path,
    width: 1280,
    height: 720,
    codecConfig: config,
  );
  Future<void> frame(ScrcpyRecorder recorder, Uint8List data, int time) =>
      recorder.addPacket(
        data,
        timestampUs: time,
        isConfig: false,
        isKeyFrame: identical(data, idr),
      );

  test(
    'waits for IDR and preserves variable timestamps and sample indexes',
    () async {
      final recorder = await start();
      await frame(recorder, predicted, 100);
      await frame(recorder, idr, 1000000);
      await frame(recorder, predicted, 1040000);
      await frame(recorder, idr, 1120000);
      expect(recorder.sampleCount, 3);
      expect(recorder.recordedDuration, const Duration(milliseconds: 120));
      expect(await recorder.finish(), path);
      expect(await recorder.finish(), path);
      expect(await File('$path.partial').exists(), false);
      final bytes = await File(path).readAsBytes();
      final mdat = box(bytes, 'mdat');
      expect(u32(bytes, mdat), 1); // extended-size header
      expect(ByteData.sublistView(bytes).getUint64(mdat + 8), 37);
      expect(u32(bytes, mdat + 16), 3); // AVCC NAL size, not a start code
      expect(bytes.sublist(mdat + 20, mdat + 23), [0x65, 0xb8, 0x80]);
      final stts = box(bytes, 'stts');
      expect(u32(bytes, stts + 12), 2);
      expect(u32(bytes, stts + 16), 1);
      expect(u32(bytes, stts + 20), 40000);
      expect(u32(bytes, stts + 24), 2);
      expect(u32(bytes, stts + 28), 80000);
      final stss = box(bytes, 'stss');
      expect(u32(bytes, stss + 12), 2);
      expect(u32(bytes, stss + 16), 1);
      expect(u32(bytes, stss + 20), 3);
      final co64 = box(bytes, 'co64');
      expect(ByteData.sublistView(bytes).getUint64(co64 + 16), mdat + 16);
      final mvhd = box(bytes, 'mvhd');
      expect(bytes[mvhd + 8], 1);
      expect(ByteData.sublistView(bytes).getUint64(mvhd + 32), 200000);
    },
  );

  test('exclusive destination refuses to overwrite an existing file', () async {
    await File(path).writeAsString('existing');
    await expectLater(start(), throwsA(isA<FileSystemException>()));
    expect(await File(path).readAsString(), 'existing');
  });

  test(
    'SPS dimensions override stale viewer dimensions in MP4 headers',
    () async {
      final recorder = await ScrcpyRecorder.start(
        path: path,
        width: 720,
        height: 1280,
        codecConfig: config,
      );
      expect(recorder.width, 1280);
      expect(recorder.height, 720);
      await frame(recorder, idr, 0);
      await recorder.finish();
      final bytes = await File(path).readAsBytes();
      final avc1 = box(bytes, 'avc1');
      // ftyp also contains avc1; find the actual sample entry in stsd.
      final entry = box(bytes, 'stsd') + 16;
      expect(entry, greaterThan(avc1));
      final data = ByteData.sublistView(bytes);
      expect(data.getUint16(entry + 32), 1280);
      expect(data.getUint16(entry + 34), 720);
    },
  );

  test(
    'high profile scaling, POC cycles and cropped interlaced SPS dimensions',
    () async {
      final fixture = Uint8List.fromList([
        0,
        0,
        1,
        ...spsFixture(
          columns: 120,
          rows: 34,
          cropBottom: 2,
          interlaced: true,
          high: true,
          scaling: true,
          pocCycle: 2,
        ),
        0,
        0,
        1,
        0x68,
        0xce,
        0x3c,
        0x80,
      ]);
      final recorder = await ScrcpyRecorder.start(
        path: path,
        width: 1,
        height: 1,
        codecConfig: fixture,
      );
      expect(recorder.width, 1920);
      expect(recorder.height, 1080);
      await frame(recorder, idr, 0);
      await recorder.finish();
    },
  );

  test(
    'SPS emulation prevention bytes are removed before decoding fields',
    () async {
      // A large bounded POC offset creates enough zero bits to require escaping.
      final sps = spsFixture(pocCycle: 1, pocOffset: 1 << 23);
      expect(sps, contains(3));
      final fixture = Uint8List.fromList([
        0,
        0,
        1,
        ...sps,
        0,
        0,
        1,
        0x68,
        0xce,
        0x3c,
        0x80,
      ]);
      final recorder = await ScrcpyRecorder.start(
        path: path,
        width: 1,
        height: 1,
        codecConfig: fixture,
      );
      expect(recorder.width, 1280);
      expect(recorder.height, 720);
      await frame(recorder, idr, 0);
      await recorder.finish();
    },
  );

  test(
    'truncated SPS and impossible cropping fail without leaving owned files',
    () async {
      for (final sps in [
        <int>[0x67, 0x42, 0, 30, 0x80],
        spsFixture(columns: 1, rows: 1, cropRight: 9),
      ]) {
        await expectLater(
          ScrcpyRecorder.start(
            path: path,
            width: 1280,
            height: 720,
            codecConfig: Uint8List.fromList([0, 0, 1, ...sps]),
          ),
          throwsA(isA<FormatException>()),
        );
        expect(await File(path).exists(), false);
        expect(await File('$path.partial').exists(), false);
      }
    },
  );

  test('unowned partial file is preserved when start fails', () async {
    await File('$path.partial').writeAsString('other partial');
    await expectLater(start(), throwsA(isA<FileSystemException>()));
    expect(await File('$path.partial').readAsString(), 'other partial');
    expect(await File(path).exists(), false);
  });

  test('no keyframe deletes only the files owned by this recorder', () async {
    final recorder = await start();
    await frame(recorder, predicted, 0);
    await expectLater(
      recorder.finish(),
      throwsA(isA<ScrcpyRecordingException>()),
    );
    expect(await File(path).exists(), false);
    expect(await File('$path.partial').exists(), false);
  });

  test('changed codec configuration saves the preceding valid clip', () async {
    final recorder = await start();
    await frame(recorder, idr, 0);
    final changed = Uint8List.fromList(config)..[7] = 31;
    await expectLater(
      recorder.addPacket(
        changed,
        timestampUs: 0,
        isConfig: true,
        isKeyFrame: false,
      ),
      throwsA(
        isA<ScrcpyRecordingException>().having(
          (e) => e.savedPath,
          'saved clip',
          path,
        ),
      ),
    );
    expect(await recorder.finish(), path);
    expect(recorder.sampleCount, 1);
    expect(box(await File(path).readAsBytes(), 'moov'), greaterThan(0));
  });

  test(
    'out-of-order timestamps and B slices stop before writing bad samples',
    () async {
      final recorder = await start();
      await frame(recorder, idr, 100);
      await expectLater(
        frame(recorder, predicted, 99),
        throwsA(
          isA<ScrcpyRecordingException>().having(
            (e) => e.savedPath,
            'path',
            path,
          ),
        ),
      );
      expect(recorder.sampleCount, 1);
      await recorder.finish();
      final other = await ScrcpyRecorder.start(
        path: '${temp.path}/b.mp4',
        width: 1280,
        height: 720,
        codecConfig: config,
      );
      await frame(other, idr, 0);
      final bFrame = Uint8List.fromList([0, 0, 1, 0x41, 0xa8]);
      await expectLater(
        frame(other, bFrame, 100),
        throwsA(isA<ScrcpyRecordingException>()),
      );
      expect(other.sampleCount, 1);
      await other.finish();
    },
  );

  test(
    'finish drains pending writes and supports more than 71 minutes',
    () async {
      final recorder = await start();
      final first = frame(recorder, idr, 0);
      final second = frame(recorder, predicted, 3600000000);
      final third = frame(recorder, predicted, 7200000000);
      final done = recorder.finish();
      await Future.wait([first, second, third]);
      await done;
      final bytes = await File(path).readAsBytes();
      final mvhd = box(bytes, 'mvhd');
      expect(ByteData.sublistView(bytes).getUint64(mvhd + 32), 10800000000);
    },
  );
}
