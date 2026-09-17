import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'scrcpy_protocol.dart';
import 'scrcpy_recorder.dart';
import 'scrcpy_service.dart';

enum ScreenStreamQuality {
  responsive('Responsive · 1280 / 30 fps', 1280, 4000000),
  tutorial('Tutorial · 1920 / 30 fps', 1920, 8000000);

  final String label;
  final int maxSize;
  final int bitRate;
  const ScreenStreamQuality(this.label, this.maxSize, this.bitRate);
}

/// Owns one embedded decoder and recording session. Recording consumes the
/// original timestamped packets, independently of playback speed or buffering.
class ScreenStreamController extends ChangeNotifier {
  final ScrcpyService service;
  final Future<String> Function() recordingPath;
  final void Function(String message, String tag) onLog;
  final bool decoderDiagnostics;
  Player? _player;
  VideoController? videoController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  ScrcpyRecorder? _recorder;
  Future<void> _recordingWrites = Future<void>.value();
  Future<void>? _starting;
  Future<void>? _closing;
  Future<void>? _recordingOperation;
  Future<void>? _stopOperation;
  Timer? _clock;
  final Stopwatch _recordingClock = Stopwatch();
  int _queuedRecordingBytes = 0;
  bool _closed = false;
  bool _disposed = false;
  bool _stoppingRecording = false;
  bool ready = false;
  String? error;
  String? recordingMessage;
  String? lastRecordingPath;
  Size videoSize = Size.zero;

  ScreenStreamController({
    required this.service,
    required this.recordingPath,
    required this.onLog,
    this.decoderDiagnostics = false,
  });

  bool get isRecording => _recorder != null;
  bool get recordingBusy => _recordingOperation != null || _stoppingRecording;
  Duration get recordingElapsed =>
      _recorder?.recordedDuration ?? _recordingClock.elapsed;
  int get recordedFrames => _recorder?.sampleCount ?? 0;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _checkOpen() {
    if (_closed) throw StateError('Screen viewer closed.');
  }

  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    try {
      if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        throw UnsupportedError('Fast streaming is available on desktop.');
      }
      _checkOpen();
      MediaKit.ensureInitialized();
      await service.start();
      _checkOpen();
      videoSize = Size(service.width.toDouble(), service.height.toDouble());
      _subscriptions.add(
        service.packets.listen(
          _onPacket,
          onError: (Object e) => _streamFailed('Screen connection lost: $e'),
          onDone: () {
            if (!_closed) _streamFailed('Screen connection ended.');
          },
        ),
      );
      final player = Player(
        configuration: PlayerConfiguration(
          title: 'OpenPelo live screen',
          bufferSize: 1024 * 1024,
          logLevel: decoderDiagnostics ? MPVLogLevel.debug : MPVLogLevel.error,
        ),
      );
      _player = player;
      if (decoderDiagnostics) {
        _subscriptions.add(
          player.stream.log.listen((event) {
            onLog('Decoder ${event.prefix}: ${event.text}', 'debug');
          }),
        );
      }
      videoController = VideoController(player);
      _notify(); // Mount the texture before waiting for decoder initialization.
      _subscriptions.add(
        player.stream.videoParams.listen((params) {
          final w = params.dw ?? params.w;
          final h = params.dh ?? params.h;
          if (w != null && h != null && w > 0 && h > 0) {
            videoSize = Size(w.toDouble(), h.toDouble());
            _notify();
          }
        }),
      );
      _subscriptions.add(
        player.stream.error.listen((message) {
          if (message.isNotEmpty && !ready) {
            onLog('Video decoder: $message', 'error');
          }
          if (message.isNotEmpty && ready) {
            _streamFailed('Video decoder: $message');
          }
        }),
      );
      _subscriptions.add(
        player.stream.completed.listen((completed) {
          if (completed) {
            _streamFailed('Video stream ended. Reconnect to resume viewing.');
          }
        }),
      );
      final native = player.platform;
      if (native is! NativePlayer) {
        throw UnsupportedError('Native video decoder unavailable.');
      }
      // Render live frames immediately. The relay wraps H.264 in MPEG-TS,
      // supported by the bundled decoder; recording uses original packet PTS.
      for (final option in const {
        'profile': 'low-latency',
        'untimed': 'yes',
        'cache': 'no',
        'audio': 'no',
        'demuxer-lavf-format': 'mpegts',
        'demuxer-lavf-probesize': '32768',
        'demuxer-lavf-analyzeduration': '0.1',
        'demuxer-readahead-secs': '0',
        'vd-lavc-threads': '1',
      }.entries) {
        await native
            .setProperty(option.key, option.value)
            .timeout(const Duration(seconds: 10));
        _checkOpen();
      }
      await player
          .open(Media(service.relayUri.toString()))
          .timeout(const Duration(seconds: 15));
      await videoController!.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 15),
      );
      _checkOpen();
      if (error != null || service.isClosed) {
        throw StateError(error ?? 'Screen connection ended during startup.');
      }
      ready = true;
      onLog(
        'Fast screen viewer connected (${service.width}×${service.height}, H.264).',
        'info',
      );
      _notify();
    } catch (e) {
      if (!_closed) {
        error = 'Fast streaming could not start: $e';
        onLog(error!, 'error');
        _notify();
      }
      rethrow;
    }
  }

  void _streamFailed(String message) {
    if (_closed || error != null) return;
    error = message;
    ready = false;
    onLog(message, 'error');
    unawaited(stopRecording());
    _notify();
  }

  void _onPacket(ScrcpyVideoPacket packet) {
    final recorder = _recorder;
    if (recorder == null || _stoppingRecording || _closed) return;
    // A slow disk must not grow an unbounded queue or stall remote input.
    if (_queuedRecordingBytes + packet.bytes.length > 16 * 1024 * 1024) {
      recordingMessage = 'Recording stopped because storage could not keep up.';
      onLog(recordingMessage!, 'error');
      unawaited(stopRecording());
      return;
    }
    _queuedRecordingBytes += packet.bytes.length;
    _recordingWrites = _recordingWrites.then((_) async {
      try {
        if (!recorder.isFinished) {
          await recorder.addPacket(
            packet.bytes,
            timestampUs: packet.timestampUs,
            isConfig: packet.isConfig,
            isKeyFrame: packet.isKeyFrame,
          );
        }
      } catch (e) {
        _recordingError(e);
      } finally {
        _queuedRecordingBytes -= packet.bytes.length;
      }
    });
  }

  void _recordingError(Object e) {
    recordingMessage = 'Recording stopped: $e';
    if (e is ScrcpyRecordingException && e.savedPath != null) {
      lastRecordingPath = e.savedPath;
    }
    onLog(recordingMessage!, 'error');
    // Do not await from within the write queue that stopRecording drains.
    unawaited(stopRecording());
    _notify();
  }

  Future<void> startRecording() async {
    if (!ready || _closed || recordingBusy || isRecording) return;
    final operation = _beginRecording();
    _recordingOperation = operation;
    _notify();
    try {
      await operation;
    } finally {
      _recordingOperation = null;
      _notify();
    }
  }

  Future<void> _beginRecording() async {
    try {
      recordingMessage = null;
      final path = await recordingPath();
      _checkOpen();
      final recorder = await ScrcpyRecorder.start(
        path: path,
        width: videoSize.width.round(),
        height: videoSize.height.round(),
        codecConfig: service.codecConfig,
      );
      if (_closed || !ready) {
        try {
          await recorder.finish();
        } catch (_) {
          /* No frames yet. */
        }
        return;
      }
      _recorder = recorder;
      _recordingClock
        ..reset()
        ..start();
      _clock = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
      onLog('Recording Peloton video to $path (no audio).', 'info');
    } catch (e) {
      recordingMessage = 'Could not start recording: $e';
      onLog(recordingMessage!, 'error');
    }
  }

  Future<void> stopRecording() => _stopOperation ??= _stopRecording()
      .whenComplete(() => _stopOperation = null);

  Future<void> _stopRecording() async {
    _stoppingRecording = true;
    _notify();
    try {
      await _recordingOperation;
      final recorder = _recorder;
      _recorder = null;
      _clock?.cancel();
      _recordingClock.stop();
      await _recordingWrites;
      if (recorder != null) {
        try {
          final path = await recorder.finish();
          lastRecordingPath = path;
          recordingMessage = recordingMessage == null
              ? 'Saved $path'
              : '$recordingMessage\nSaved $path';
          onLog('Tutorial recording saved to $path', 'info');
        } catch (e) {
          recordingMessage = 'Recording ended: $e';
          if (e is ScrcpyRecordingException && e.savedPath != null) {
            lastRecordingPath = e.savedPath;
          }
          onLog(recordingMessage!, 'error');
        }
      }
    } finally {
      _stoppingRecording = false;
      _notify();
    }
  }

  Future<void> key(int code) async {
    if (!ready || _closed) return;
    await service.injectKeycode(keycode: code, action: ScrcpyKeyAction.down);
    await service.injectKeycode(keycode: code, action: ScrcpyKeyAction.up);
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    ready = false;
    await stopRecording();
    await service.close();
    try {
      await _starting;
    } catch (_) {
      /* Startup failure is shown by UI. */
    }
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final player = _player;
    _player = null;
    if (player != null) await player.dispose();
    videoController = null;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}
