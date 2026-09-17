// Opt-in native texture/recording smoke app. Uses the same environment variables
// as scrcpy_smoke_test.dart; writes <OPENPELO_SMOKE_OUTPUT>.json and exits.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import 'package:openpelo/services/adb_service.dart';
import 'package:openpelo/services/scrcpy_service.dart';
import 'package:openpelo/services/screen_stream_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setOpacity(0);
  final env = Platform.environment;
  final output = env['OPENPELO_SMOKE_OUTPUT']!;
  final logs = <String>[];
  final controller = ScreenStreamController(
    decoderDiagnostics: true,
    service: ScrcpyService(
      adbService: AdbService(
        executablePath: env['OPENPELO_SMOKE_ADB']!,
        onLog: (message, tag) => logs.add('$tag: $message'),
      ),
      serial: env['OPENPELO_SMOKE_SERIAL']!,
      maxSize: 1920,
      videoBitRate: 8000000,
    ),
    recordingPath: () async => output,
    onLog: (message, tag) => logs.add('$tag: $message'),
  );
  runApp(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, child) => controller.videoController == null
              ? const SizedBox()
              : Video(
                  controller: controller.videoController!,
                  controls: NoVideoControls,
                ),
        ),
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final result = <String, Object?>{};
    try {
      await controller.start();
      result['ready'] = controller.ready;
      result['width'] = controller.videoSize.width;
      result['height'] = controller.videoSize.height;
      await controller.startRecording();
      await Future<void>.delayed(const Duration(seconds: 5));
      result['frames'] = controller.recordedFrames;
      await controller.stopRecording();
      result['path'] = controller.lastRecordingPath;
      result['recordingMessage'] = controller.recordingMessage;
      if (!controller.ready || controller.lastRecordingPath == null) {
        throw StateError(controller.error ?? 'Recording not saved');
      }
    } catch (error, stack) {
      result['error'] = '$error\n$stack';
    } finally {
      await controller.close();
      result['logs'] = logs;
      await File(
        '$output.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
      exit(result.containsKey('error') ? 1 : 0);
    }
  });
}
