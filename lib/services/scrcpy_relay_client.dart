import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'scrcpy_mpeg_ts.dart';
import 'scrcpy_protocol.dart';

/// Each player has a small queue. A stalled decoder is disconnected instead
/// of retaining an unlimited compressed video backlog in the application.
class ScrcpyRelayClient {
  static const int maxQueuedBytes = 4 * 1024 * 1024;
  final HttpResponse response;
  final ScrcpyMpegTsMuxer _muxer = ScrcpyMpegTsMuxer();
  final Queue<Uint8List> _queue = Queue<Uint8List>();
  int _queuedBytes = 0;
  bool _writing = false;
  bool _closed = false;
  bool _awaitKeyframe = true;
  Timer? _keepAlive;
  Future<void>? _pendingFlush;

  ScrcpyRelayClient(this.response) {
    unawaited(
      response.done.then((_) => close(), onError: (Object _) => close()),
    );
    // Null TS packets carry no video or timestamps. They let the decoder's
    // HTTP reads complete while the device display is idle, including during
    // probing of a small initial frame. Never inject these into recordings.
    _keepAlive = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_queue.isEmpty && !_writing) _enqueue(_idlePadding);
    });
  }

  static final Uint8List _idlePadding = (() {
    // Exceed the decoder's 32 KiB probe/read buffer even on a tiny still frame.
    final bytes = Uint8List(188 * 192);
    bytes.fillRange(0, bytes.length, 0xff);
    for (var offset = 0; offset < bytes.length; offset += 188) {
      bytes.setRange(offset, offset + 4, const [0x47, 0x1f, 0xff, 0x10]);
    }
    return bytes;
  })();

  bool addConfig(Uint8List bytes) {
    if (_closed) return false;
    _awaitKeyframe = true;
    _muxer.addConfig(bytes);
    return true;
  }

  bool addPacket(ScrcpyVideoPacket packet) {
    if (_closed) return false;
    if (packet.isConfig) return addConfig(packet.bytes);
    if (_awaitKeyframe) {
      if (!packet.isKeyFrame) return true;
      _awaitKeyframe = false;
    }
    try {
      return _enqueue(_muxer.mux(packet));
    } catch (_) {
      close();
      return false;
    }
  }

  bool _enqueue(Uint8List bytes) {
    if (_closed) return false;
    if (_queuedBytes + bytes.length > maxQueuedBytes) {
      close();
      return false;
    }
    _queue.add(bytes);
    _queuedBytes += bytes.length;
    if (!_writing) unawaited(_drain());
    return true;
  }

  Future<void> _drain() async {
    _writing = true;
    try {
      while (!_closed && _queue.isNotEmpty) {
        final bytes = _queue.removeFirst();
        _queuedBytes -= bytes.length;
        response.add(bytes);
        _pendingFlush = response.flush();
        await _pendingFlush!.timeout(const Duration(seconds: 2));
      }
    } catch (_) {
      close();
    } finally {
      _writing = false;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _keepAlive?.cancel();
    _queue.clear();
    _queuedBytes = 0;
    unawaited(_closeResponse());
  }

  Future<void> _closeResponse() async {
    try {
      // HttpResponse.close throws while flush has the sink bound. Cleanup can
      // race with that flush after the reader receives the last chunk.
      await _pendingFlush;
      await response.close();
    } catch (_) {
      // A disconnected reader may already have closed the response.
    }
  }
}
