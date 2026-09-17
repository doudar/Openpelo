import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import 'adb_service.dart';
import 'scrcpy_mpeg_ts.dart';
import 'scrcpy_protocol.dart';

/// A single, owned scrcpy v3.3.4 server session for a desktop ADB device.
/// [packets] is broadcast: attach recorders after [start], and use
/// [codecConfig] to seed a recorder started after the initial config packet.
class ScrcpyService {
  static const String serverAsset = 'assets/scrcpy/scrcpy-server-v3.3.4';
  static const String serverVersion = '3.3.4';

  final AdbService adbService;
  final String serial;
  final int maxSize;
  final int maxFps;
  final int videoBitRate;
  final StreamController<ScrcpyVideoPacket> _packets =
      StreamController<ScrcpyVideoPacket>.broadcast(sync: true);

  Process? _process;
  Socket? _videoSocket;
  Socket? _controlSocket;
  _SocketReader? _videoReader;
  HttpServer? _relay;
  StreamSubscription<ScrcpyVideoPacket>? _relaySubscription;
  final Set<_RelayClient> _relayClients = {};
  String? _remoteServer;
  int? _forwardPort;
  bool _closed = false;
  Future<void>? _startFuture;
  Future<void>? _cleanupFuture;
  Uint8List? _codecConfig;

  late final int width;
  late final int height;
  late final String deviceName;
  late final Uri relayUri;
  late final String _relayPath;

  ScrcpyService({
    required this.adbService,
    required this.serial,
    this.maxSize = 1280,
    this.maxFps = 30,
    this.videoBitRate = 4000000,
  }) {
    if (maxSize < 0 ||
        maxSize > 16384 ||
        maxFps < 1 ||
        maxFps > 120 ||
        videoBitRate < 100000 ||
        videoBitRate > 100000000) {
      throw ArgumentError('Invalid scrcpy video settings');
    }
  }

  Stream<ScrcpyVideoPacket> get packets => _packets.stream;
  Uint8List? get codecConfig =>
      _codecConfig == null ? null : Uint8List.fromList(_codecConfig!);
  bool get isClosed => _closed;

  Future<void> start() {
    if (_closed || _process != null) {
      throw StateError('Session already started');
    }
    if (_startFuture != null) throw StateError('Session already starting');
    _startFuture = _startInternal();
    return _startFuture!;
  }

  Future<void> _startInternal() async {
    if (adbService.isMobile) {
      throw UnsupportedError('Embedded scrcpy requires desktop ADB');
    }
    try {
      final scid = Random.secure().nextInt(0x7fffffff) + 1;
      final scidHex = scid.toRadixString(16).padLeft(8, '0');
      _remoteServer = '/data/local/tmp/openpelo-scrcpy-$scidHex.jar';

      // The asset is a pinned upstream server, not a PackageManager install.
      final asset = await rootBundle.load(serverAsset);
      _ensureOpen();
      final localFile = await File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'openpelo-scrcpy-$scidHex.jar',
      ).create();
      try {
        await localFile.writeAsBytes(
          asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
          flush: true,
        );
        await adbService.runAdbCommand(
          ['-s', serial, 'push', localFile.path, _remoteServer!],
          timeout: const Duration(seconds: 30),
          logOutput: false,
        );
        _ensureOpen();
      } finally {
        await localFile.delete().catchError((Object _) => localFile);
      }

      final forward = await adbService.runAdbCommand(
        [
          '-s',
          serial,
          'forward',
          '--no-rebind',
          'tcp:0',
          'localabstract:scrcpy_$scidHex',
        ],
        timeout: const Duration(seconds: 10),
        logOutput: false,
      );
      _forwardPort = int.tryParse(forward.stdout.toString().trim());
      if (_forwardPort == null || _forwardPort! <= 0 || _forwardPort! > 65535) {
        throw StateError('ADB did not return a scrcpy forward port');
      }
      _ensureOpen();

      // scid is parsed as hexadecimal by scrcpy. A single shell command keeps
      // CLASSPATH local to this owned server process.
      _process = await adbService.startAdbProcess([
        '-s',
        serial,
        'shell',
        'CLASSPATH=$_remoteServer app_process / com.genymobile.scrcpy.Server '
            '$serverVersion scid=$scidHex video=true audio=false control=true '
            'tunnel_forward=true video_codec=h264 send_frame_meta=true '
            'send_codec_meta=true send_device_meta=true send_dummy_byte=true '
            'max_size=$maxSize max_fps=$maxFps video_bit_rate=$videoBitRate '
            'video_codec_options=max-bframes:int=0,i-frame-interval:int=1 '
            'cleanup=false',
      ]);
      _ensureOpen();
      _drainProcess(_process!);

      await _openSocketsAndReadHeader();
      _ensureOpen();
      // The control channel is bidirectional (clipboard and device messages).
      // Even when ignored, its incoming bytes must be drained.
      _controlSocket!.listen((_) {}, onError: (Object _) {});

      await _startRelay();
      _ensureOpen();
      unawaited(_readPackets());
    } catch (_) {
      _closed = true;
      await _cleanup();
      rethrow;
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('scrcpy session closed during startup');
  }

  Future<void> _openSocketsAndReadHeader() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    Object? lastError;
    while (!_closed && DateTime.now().isBefore(deadline)) {
      try {
        // The server accepts video before control. Both connections may reach
        // ADB's local forward before the remote server has bound its socket;
        // retry the complete handshake if that yields an early EOF.
        _videoSocket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          _forwardPort!,
          timeout: const Duration(seconds: 1),
        );
        _controlSocket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          _forwardPort!,
          timeout: const Duration(seconds: 1),
        );
        _videoSocket!.setOption(SocketOption.tcpNoDelay, true);
        _controlSocket!.setOption(SocketOption.tcpNoDelay, true);
        _videoReader = _SocketReader(_videoSocket!);
        final dummy = await _videoReader!.readExactly(
          1,
          timeout: const Duration(seconds: 2),
        );
        if (dummy[0] != 0) {
          throw const FormatException('Invalid scrcpy dummy byte');
        }
        final nameBytes = await _videoReader!.readExactly(
          64,
          timeout: const Duration(seconds: 2),
        );
        final parsedName = utf8.decode(
          nameBytes.takeWhile((b) => b != 0).toList(),
          allowMalformed: true,
        );
        final header = ScrcpyProtocol.parseVideoHeader(
          await _videoReader!.readExactly(
            12,
            timeout: const Duration(seconds: 2),
          ),
        );
        // Do not assign late final fields until every part of the handshake
        // is valid: a failed attempt must be free to retry.
        deviceName = parsedName;
        width = header.width;
        height = header.height;
        return;
      } catch (error) {
        lastError = error;
        _videoReader?.close();
        _videoSocket?.destroy();
        _controlSocket?.destroy();
        _videoReader = null;
        _videoSocket = null;
        _controlSocket = null;
        if (_closed) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw TimeoutException('scrcpy handshake did not complete: $lastError');
  }

  void _drainProcess(Process process) {
    void logLine(String line, String tag) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        adbService.onLog(
          trimmed.length > 1000 ? trimmed.substring(0, 1000) : trimmed,
          tag,
        );
      }
    }

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => logLine(line, 'stdout'));
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => logLine(line, 'stderr'));
  }

  Future<void> _readPackets() async {
    try {
      while (!_closed) {
        // A still screen can produce no frames for arbitrarily long periods.
        final raw = await _videoReader!.readExactly(12);
        final frame = ScrcpyProtocol.parseFrameHeader(raw);
        final bytes = await _videoReader!.readExactly(
          frame.size,
          timeout: const Duration(seconds: 10),
        );
        if (frame.isConfig) _codecConfig = bytes;
        _packets.add(
          ScrcpyVideoPacket(
            bytes: bytes,
            timestampUs: frame.timestampUs,
            isConfig: frame.isConfig,
            isKeyFrame: frame.isKeyFrame,
          ),
        );
      }
    } catch (error, stack) {
      if (!_closed) {
        _packets.addError(error, stack);
        unawaited(close());
      }
    }
  }

  Future<void> _startRelay() async {
    _relay = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final token = List<int>.generate(
      16,
      (_) => Random.secure().nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _relayPath = '/$token/video.ts';
    relayUri = Uri.parse('http://127.0.0.1:${_relay!.port}$_relayPath');
    _relay!.listen((request) {
      if (request.method != 'GET' || request.uri.path != _relayPath) {
        request.response.statusCode = HttpStatus.notFound;
        unawaited(request.response.close());
        return;
      }
      final response = request.response;
      response.headers.contentType = ContentType('video', 'mp2t');
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.bufferOutput = false;
      for (final oldClient in _relayClients.toList()) {
        oldClient.close();
      }
      _relayClients.clear();
      final client = _RelayClient(response);
      _relayClients.add(client);
      if (_codecConfig != null) client.addConfig(_codecConfig!);
      unawaited(
        response.done.then(
          (_) {
            _relayClients.remove(client);
          },
          onError: (Object _) {
            _relayClients.remove(client);
          },
        ),
      );
    });
    _relaySubscription = packets.listen(
      (packet) {
        for (final client in _relayClients.toList()) {
          if (!client.addPacket(packet)) _relayClients.remove(client);
        }
      },
      onError: (Object _, StackTrace _) {
        for (final client in _relayClients.toList()) {
          client.close();
        }
        _relayClients.clear();
      },
    );
  }

  void _send(Uint8List bytes) {
    if (_closed || _controlSocket == null) throw StateError('scrcpy is closed');
    _controlSocket!.add(bytes);
  }

  Future<void> injectTouch({
    required ScrcpyTouchAction action,
    required int x,
    required int y,
    int? videoWidth,
    int? videoHeight,
    int pointerId = -2,
  }) async {
    _send(
      ScrcpyProtocol.touch(
        action: action.value,
        x: x,
        y: y,
        width: videoWidth ?? width,
        height: videoHeight ?? height,
        pointerId: pointerId,
        pressure: action == ScrcpyTouchAction.up ? 0 : 1,
      ),
    );
    await _controlSocket!.flush();
  }

  Future<void> injectKeycode({
    required int keycode,
    ScrcpyKeyAction action = ScrcpyKeyAction.down,
    int repeat = 0,
    int metaState = 0,
  }) async {
    _send(
      ScrcpyProtocol.keycode(
        keycode: keycode,
        action: action.value,
        repeat: repeat,
        metaState: metaState,
      ),
    );
    await _controlSocket!.flush();
  }

  Future<void> injectText(String text) async {
    _send(ScrcpyProtocol.text(text));
    await _controlSocket!.flush();
  }

  Future<void> injectScroll({
    required int x,
    required int y,
    double horizontal = 0,
    double vertical = 0,
    int? videoWidth,
    int? videoHeight,
  }) async {
    _send(
      ScrcpyProtocol.scroll(
        x: x,
        y: y,
        width: videoWidth ?? width,
        height: videoHeight ?? height,
        horizontal: horizontal,
        vertical: vertical,
      ),
    );
    await _controlSocket!.flush();
  }

  Future<void> backOrScreenOn(ScrcpyKeyAction action) async {
    _send(ScrcpyProtocol.backOrScreenOn(action.value));
    await _controlSocket!.flush();
  }

  Future<void> close() async {
    _closed = true;
    if (_startFuture != null) {
      try {
        await _startFuture;
      } catch (_) {}
    }
    await _cleanup();
  }

  Future<void> _cleanup() => _cleanupFuture ??= _doCleanup();

  Future<void> _doCleanup() async {
    await _relaySubscription?.cancel();
    for (final client in _relayClients.toList()) {
      client.close();
    }
    _relayClients.clear();
    await _relay?.close(force: true);
    _videoReader?.close();
    _videoSocket?.destroy();
    _controlSocket?.destroy();
    _process?.kill();
    if (_process != null) {
      await _process!.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () => -1,
      );
    }
    if (_forwardPort != null) {
      try {
        await adbService.runAdbCommand(
          ['-s', serial, 'forward', '--remove', 'tcp:$_forwardPort'],
          allowFailure: true,
          timeout: const Duration(seconds: 3),
          logOutput: false,
        );
      } catch (_) {}
    }
    if (_remoteServer != null) {
      try {
        await adbService.runAdbCommand(
          ['-s', serial, 'shell', 'rm', '-f', _remoteServer!],
          allowFailure: true,
          timeout: const Duration(seconds: 3),
          logOutput: false,
        );
      } catch (_) {}
    }
    await _packets.close();
  }
}

/// StreamIterator pauses its subscription between reads, so a slow consumer
/// applies TCP backpressure instead of retaining an unbounded Dart byte queue.
class _SocketReader {
  final StreamIterator<Uint8List> _iterator;
  Uint8List _chunk = Uint8List(0);
  int _offset = 0;

  _SocketReader(Socket socket) : _iterator = StreamIterator<Uint8List>(socket);

  Future<Uint8List> readExactly(int length, {Duration? timeout}) async {
    if (length < 0 || length > ScrcpyProtocol.maxPacketSize) {
      throw RangeError.range(length, 0, ScrcpyProtocol.maxPacketSize);
    }
    final result = Uint8List(length);
    var copied = 0;
    while (copied < length) {
      if (_offset == _chunk.length) {
        final next = _iterator.moveNext();
        if (!await (timeout == null ? next : next.timeout(timeout))) {
          throw const SocketException('scrcpy video socket closed');
        }
        _chunk = _iterator.current;
        _offset = 0;
        continue;
      }
      final count = min(length - copied, _chunk.length - _offset);
      result.setRange(copied, copied + count, _chunk, _offset);
      copied += count;
      _offset += count;
    }
    return result;
  }

  void close() => unawaited(_iterator.cancel());
}

/// Each player has a small queue. A stalled decoder is disconnected instead
/// of retaining an unlimited compressed video backlog in the application.
class _RelayClient {
  static const int maxQueuedBytes = 4 * 1024 * 1024;
  final HttpResponse response;
  final ScrcpyMpegTsMuxer _muxer = ScrcpyMpegTsMuxer();
  final Queue<Uint8List> _queue = Queue<Uint8List>();
  int _queuedBytes = 0;
  bool _writing = false;
  bool _closed = false;
  bool _awaitKeyframe = true;

  _RelayClient(this.response);

  bool addConfig(Uint8List bytes) {
    _awaitKeyframe = true;
    _muxer.addConfig(bytes);
    return true;
  }

  bool addPacket(ScrcpyVideoPacket packet) {
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
        await response.flush().timeout(const Duration(seconds: 2));
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
    _queue.clear();
    _queuedBytes = 0;
    unawaited(response.close());
  }
}
