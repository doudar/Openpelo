import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../models/device_model.dart';
import '../providers/app_provider.dart';
import '../services/screen_input.dart';
import '../services/screen_stream_controller.dart';
import '../services/scrcpy_protocol.dart';
import 'draggable_dialog.dart';
import 'screenshot_mirror_dialog.dart';

class ScreenMirrorDialog extends StatefulWidget {
  const ScreenMirrorDialog({super.key});

  @override
  State<ScreenMirrorDialog> createState() => _ScreenMirrorDialogState();
}

class _ScreenMirrorDialogState extends State<ScreenMirrorDialog>
    with WindowListener {
  final FocusNode _focus = FocusNode();
  late final AppProvider _provider;
  late final DeviceModel? _target;
  ScreenStreamController? _stream;
  ScreenStreamQuality _quality = ScreenStreamQuality.responsive;
  bool _starting = false;
  bool _closing = false;
  Future<void>? _closeFuture;
  bool _fallback = false;
  bool _expanded = false;
  String? _fallbackReason;
  Offset? _lastPoint;
  int? _pointer;
  DateTime _lastMove = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _inputQueue = Future<void>.value();
  int _pendingInput = 0;

  bool get _desktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  bool get _sameDevice =>
      _target != null &&
      _provider.selectedDevice?.serial == _target.serial &&
      _provider.selectedDevice?.identityKey == _target.identityKey;

  @override
  void initState() {
    super.initState();
    _provider = context.read<AppProvider>();
    _target = _provider.selectedDevice;
    _provider.addListener(_deviceChanged);
    if (_desktop) {
      windowManager.addListener(this);
      unawaited(_protectWindowClose());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_start());
        _focus.requestFocus();
      }
    });
  }

  Future<void> _protectWindowClose() async {
    await windowManager.setPreventClose(true);
    if (!mounted) await windowManager.setPreventClose(false);
  }

  @override
  void onWindowClose() {
    unawaited(_closeApplication());
  }

  Future<void> _closeApplication() async {
    await _close();
    // The ordinary window close button must finalize an active MP4 too.
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  void _deviceChanged() {
    if (!_sameDevice && !_closing) unawaited(_close());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    if (_starting || _closing || !mounted) return;
    if (!_desktop) {
      setState(() {
        _fallback = true;
        _fallbackReason =
            'Compatibility preview: fast streaming requires desktop OpenPelo.';
      });
      return;
    }
    if (!_sameDevice) {
      await _close();
      return;
    }
    setState(() {
      _starting = true;
      _fallback = false;
      _fallbackReason = null;
    });
    try {
      final old = _stream;
      if (old != null) {
        old.removeListener(_changed);
        await old.close();
        old.dispose();
        _stream = null;
      }
      _pointer = null;
      _lastPoint = null;
      if (!mounted || _closing) return;
      final stream = ScreenStreamController(
        service: _provider.createScreenStream(
          maxSize: _quality.maxSize,
          bitRate: _quality.bitRate,
        ),
        recordingPath: _provider.nextScreenRecordingPath,
        onLog: _provider.logScreenActivity,
      );
      _stream = stream;
      stream.addListener(_changed);
      _provider.setScreenStreamActive(true);
      await stream.start();
    } catch (e) {
      await _stream?.close();
      _provider.setScreenStreamActive(false);
      if (mounted && !_closing) {
        setState(() {
          _fallback = true;
          _fallbackReason =
              'Using compatibility screenshots. Fast streaming unavailable: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _useFallback() async {
    if (_closing || _starting) return;
    setState(() => _starting = true);
    await _stream?.close();
    _provider.setScreenStreamActive(false);
    if (mounted) {
      setState(() {
        _starting = false;
        _fallback = true;
        _fallbackReason = 'Compatibility screenshot preview selected.';
      });
    }
  }

  Future<void> _close() => _closeFuture ??= _finishClose();

  Future<void> _finishClose() async {
    setState(() => _closing = true);
    await _stream?.close();
    _provider.setScreenStreamActive(false);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    if (_desktop) {
      windowManager.removeListener(this);
      unawaited(windowManager.setPreventClose(false));
    }
    _provider.removeListener(_deviceChanged);
    _stream?.removeListener(_changed);
    final stream = _stream;
    if (stream != null) {
      unawaited(
        stream.close().whenComplete(() {
          _provider.setScreenStreamActive(false);
          stream.dispose();
        }),
      );
    }
    _focus.dispose();
    super.dispose();
  }

  void _input(
    Future<void> Function(ScreenStreamController) action, {
    bool disposable = false,
  }) {
    final stream = _stream;
    if (!_sameDevice ||
        stream == null ||
        !stream.ready ||
        _closing ||
        _starting) {
      return;
    }
    if (disposable && _pendingInput >= 8) return;
    _pendingInput++;
    _inputQueue = _inputQueue
        .then((_) async {
          if (_sameDevice &&
              identical(stream, _stream) &&
              stream.ready &&
              !_closing) {
            await action(stream).timeout(const Duration(seconds: 3));
          }
        })
        .catchError((Object error) {
          _provider.logScreenActivity('Screen input failed: $error', 'error');
        })
        .whenComplete(() => _pendingInput--);
  }

  Offset? _map(Offset point, Size viewport, {bool clamp = false}) =>
      mapScreenPoint(
        point,
        viewport,
        _stream?.videoSize ?? Size.zero,
        clamp: clamp,
      );

  void _touch(
    ScrcpyTouchAction action,
    Offset point, {
    bool disposable = false,
  }) {
    final size = _stream!.videoSize;
    _input(
      (stream) => stream.service.injectTouch(
        action: action,
        x: point.dx.round(),
        y: point.dy.round(),
        videoWidth: size.width.round(),
        videoHeight: size.height.round(),
      ),
      disposable: disposable,
    );
  }

  void _pointerDown(PointerDownEvent event, Size viewport) {
    _focus.requestFocus();
    if (_pointer != null) return;
    if (event.buttons == kSecondaryMouseButton) {
      _input((stream) => stream.key(4));
      return;
    }
    if (event.buttons == kMiddleMouseButton) {
      _input((stream) => stream.key(3));
      return;
    }
    final point = _map(event.localPosition, viewport);
    if (point == null || !(_stream?.ready ?? false)) return;
    _pointer = event.pointer;
    _lastPoint = point;
    _touch(ScrcpyTouchAction.down, point);
  }

  void _pointerMove(PointerMoveEvent event, Size viewport) {
    if (_pointer != event.pointer) return;
    final point = _map(event.localPosition, viewport, clamp: true);
    if (point == null) return;
    _lastPoint = point;
    final now = DateTime.now();
    if (now.difference(_lastMove) < const Duration(milliseconds: 16)) return;
    _lastMove = now;
    _touch(ScrcpyTouchAction.move, point, disposable: true);
  }

  void _pointerUp(int pointer) {
    if (_pointer != pointer) return;
    final point = _lastPoint;
    _pointer = null;
    if (point != null && _stream != null) _touch(ScrcpyTouchAction.up, point);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final code = androidKeycode(event.logicalKey);
    if (code != null) {
      _input((stream) => stream.key(code));
      return KeyEventResult.handled;
    }
    final text = event.character;
    if (text != null &&
        text.isNotEmpty &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      _input((stream) => stream.service.injectText(text));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _elapsed(Duration elapsed) =>
      '${elapsed.inMinutes.toString().padLeft(2, '0')}:'
      '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (_fallback) {
      return ScreenshotMirrorDialog(
        reason: _fallbackReason,
        onTryStreaming: _desktop && !_closing && !_starting ? _start : null,
      );
    }
    final stream = _stream;
    final ready = stream?.ready ?? false;
    final recording = stream?.isRecording ?? false;
    final recordingBusy = stream?.recordingBusy ?? false;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_close());
      },
      child: DraggableDialog(
        width: _expanded ? double.infinity : 1100,
        height: _expanded ? double.infinity : 760,
        title: const Text(
          'Remote screen',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: _expanded ? 'Restore viewer size' : 'Expand viewer',
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(_expanded ? Icons.fullscreen_exit : Icons.fullscreen),
          ),
          IconButton(
            tooltip: 'Close viewer',
            onPressed: _closing ? null : _close,
            icon: const Icon(Icons.close),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 130),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 260,
                        child: DropdownButtonFormField<ScreenStreamQuality>(
                          initialValue: _quality,
                          decoration: const InputDecoration(
                            labelText: 'Video quality',
                          ),
                          isExpanded: true,
                          items: [
                            for (final quality in ScreenStreamQuality.values)
                              DropdownMenuItem(
                                value: quality,
                                child: Text(quality.label),
                              ),
                          ],
                          onChanged:
                              _starting ||
                                  _closing ||
                                  recording ||
                                  recordingBusy
                              ? null
                              : (quality) {
                                  if (quality == null || quality == _quality) {
                                    return;
                                  }
                                  setState(() => _quality = quality);
                                  unawaited(_start());
                                },
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: !ready || recordingBusy || _closing
                            ? null
                            : () async {
                                if (recording) {
                                  await stream!.stopRecording();
                                } else {
                                  await stream!.startRecording();
                                }
                              },
                        icon: Icon(
                          recording ? Icons.stop : Icons.fiber_manual_record,
                        ),
                        label: Text(
                          recording
                              ? 'Stop ${_elapsed(stream!.recordingElapsed)}'
                              : 'Record MP4',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: ready ? _provider.takeScreenshot : null,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Screenshot'),
                      ),
                      TextButton(
                        onPressed: _starting || _closing ? null : _useFallback,
                        child: const Text('Compatibility mode'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Focus(
                  focusNode: _focus,
                  onKeyEvent: _key,
                  onFocusChange: (focused) {
                    if (!focused && _pointer != null) _pointerUp(_pointer!);
                  },
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final viewport = constraints.biggest;
                      return Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (event) => _pointerDown(event, viewport),
                        onPointerMove: (event) => _pointerMove(event, viewport),
                        onPointerUp: (event) => _pointerUp(event.pointer),
                        onPointerCancel: (event) => _pointerUp(event.pointer),
                        onPointerSignal: (event) {
                          if (event is! PointerScrollEvent) return;
                          final point = _map(event.localPosition, viewport);
                          if (point == null) return;
                          final size = stream!.videoSize;
                          _input(
                            (stream) => stream.service.injectScroll(
                              x: point.dx.round(),
                              y: point.dy.round(),
                              vertical: (-event.scrollDelta.dy / 100)
                                  .clamp(-1, 1)
                                  .toDouble(),
                              horizontal: (-event.scrollDelta.dx / 100)
                                  .clamp(-1, 1)
                                  .toDouble(),
                              videoWidth: size.width.round(),
                              videoHeight: size.height.round(),
                            ),
                            disposable: true,
                          );
                        },
                        child: ColoredBox(
                          color: Colors.black,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (stream?.videoController != null)
                                IgnorePointer(
                                  child: Video(
                                    controller: stream!.videoController!,
                                    controls: NoVideoControls,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              if (!ready)
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_starting || _closing)
                                          const CircularProgressIndicator(),
                                        const SizedBox(height: 10),
                                        Text(
                                          _closing
                                              ? 'Saving recording and closing…'
                                              : stream?.error ??
                                                    'Connecting to the Peloton…',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        if (!_starting &&
                                            !_closing &&
                                            stream?.error != null)
                                          TextButton(
                                            onPressed: _start,
                                            child: const Text('Reconnect'),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                alignment: WrapAlignment.center,
                children: [
                  for (final item in [
                    (4, Icons.arrow_back, 'Back'),
                    (3, Icons.home_outlined, 'Home'),
                    (187, Icons.crop_square, 'Recents'),
                  ])
                    TextButton.icon(
                      onPressed: ready
                          ? () => _input((stream) => stream.key(item.$1))
                          : null,
                      icon: Icon(item.$2, size: 18),
                      label: Text(item.$3),
                    ),
                  TextButton.icon(
                    onPressed: stream?.lastRecordingPath == null
                        ? null
                        : () => _provider.openSaveLocation(
                            path: p.dirname(stream!.lastRecordingPath!),
                          ),
                    icon: const Icon(Icons.folder_outlined, size: 18),
                    label: const Text('Recordings'),
                  ),
                ],
              ),
              Text(
                stream?.recordingMessage ??
                    (recording && stream!.recordedFrames == 0
                        ? 'Waiting for a video keyframe…'
                        : 'Click, drag, scroll or type • MP4 recordings contain screen video only'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
