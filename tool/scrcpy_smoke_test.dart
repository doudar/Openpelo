// Opt-in hardware check; not part of the default test suite.
// ignore_for_file: avoid_print
// OPENPELO_SMOKE_ADB, OPENPELO_SMOKE_SERIAL, OPENPELO_SMOKE_FFMPEG and
// OPENPELO_SMOKE_OUTPUT must be set. Opens a read-only screen stream for 8s.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/services/adb_service.dart';
import 'package:openpelo/services/scrcpy_recorder.dart';
import 'package:openpelo/services/scrcpy_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'hardware stream relays decodable H264 and records an MP4',
    () async {
      final env = Platform.environment;
      final service = ScrcpyService(
        adbService: AdbService(
          executablePath: env['OPENPELO_SMOKE_ADB']!,
          onLog: (message, tag) => print('$tag: $message'),
        ),
        serial: env['OPENPELO_SMOKE_SERIAL']!,
        maxSize: 1920,
        videoBitRate: 8000000,
      );
      ScrcpyRecorder? recorder;
      StreamSubscription<dynamic>? subscription;
      var writes = Future<void>.value();
      try {
        await service.start();
        recorder = await ScrcpyRecorder.start(
          path: env['OPENPELO_SMOKE_OUTPUT']!,
          width: service.width,
          height: service.height,
          codecConfig: service.codecConfig,
        );
        final recording = recorder;
        subscription = service.packets.listen((packet) {
          writes = writes.then(
            (_) => recording.addPacket(
              packet.bytes,
              timestampUs: packet.timestampUs,
              isConfig: packet.isConfig,
              isKeyFrame: packet.isKeyFrame,
            ),
          );
        });
        final decoded = await Process.run(env['OPENPELO_SMOKE_FFMPEG']!, [
          '-v',
          'error',
          '-f',
          'mpegts',
          '-i',
          service.relayUri.toString(),
          '-t',
          '8',
          '-f',
          'null',
          '-',
        ]).timeout(const Duration(seconds: 35));
        expect(decoded.exitCode, 0, reason: decoded.stderr.toString());
        expect(decoded.stderr.toString(), isEmpty);
        await subscription.cancel();
        subscription = null;
        await writes;
        expect(recording.sampleCount, greaterThan(10));
        await recording.finish();
        print(
          'Recorded ${recording.sampleCount} frames to ${env['OPENPELO_SMOKE_OUTPUT']}',
        );
      } finally {
        await subscription?.cancel();
        await service.close();
        await writes;
        if (recorder != null && !recorder.isFinished) await recorder.finish();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: Platform.environment['OPENPELO_SMOKE_SERIAL'] == null,
  );
}
