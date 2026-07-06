import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import 'draggable_dialog.dart';

class ScreenMirrorDialog extends StatefulWidget {
  const ScreenMirrorDialog({super.key});

  @override
  State<ScreenMirrorDialog> createState() => _ScreenMirrorDialogState();
}

class _ScreenMirrorDialogState extends State<ScreenMirrorDialog> {
  Uint8List? _currentImage;
  bool _isLoading = true;
  Timer? _timer;
  bool _isProcessing = false;
  Size? _imageSize;
  Offset? _panStart;
  Offset? _panLast;
  Offset _visualDragOffset = Offset.zero;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _startLoop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _startLoop() {
    // Poll every 500ms on desktop, maybe 2s on mobile?
    // Let's just loop immediately after previous finishes with a small delay
    _fetchFrame();
  }

  Future<void> _fetchFrame() async {
    if (!mounted) return;
    if (_isProcessing) return; // Prevent overlapping

    setState(() {
       _isProcessing = true;
    });

    try {
      final provider = Provider.of<AppProvider>(context, listen: false);
      if (provider.selectedDevice == null) {
         if (mounted) Navigator.pop(context);
         return;
      }
      
      final bytes = await provider.getScreenShotBytes();
      
      if (mounted) {
         if (bytes != null && bytes.isNotEmpty && _imageSize == null) {
            _imageSize = await _decodeImageSize(bytes);
            if (!mounted) return;
         }
         setState(() {
            if (bytes != null && bytes.isNotEmpty) {
               _currentImage = bytes;
               _visualDragOffset = Offset.zero;
            }
            _isLoading = false;
         });
      }
    } catch (e) {
       // ignore
    } finally {
      if (mounted) {
         setState(() {
            _isProcessing = false;
         });
         // Schedule next frame
         // Adaptive delay? 
         // If it took 100ms, wait 100ms.
         // If it took 2s (mobile), wait 500ms.
         _timer = Timer(const Duration(milliseconds: 500), _fetchFrame);
      }
    }
  }

  Future<Size?> _decodeImageSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  Offset? _mapPreviewPoint(
    Offset localPosition,
    BoxConstraints constraints,
  ) {
    final imageSize = _imageSize;
    if (imageSize == null || _currentImage == null) return null;

    final boxSize = Size(constraints.maxWidth, constraints.maxHeight);
    final imageAspect = imageSize.width / imageSize.height;
    final boxAspect = boxSize.width / boxSize.height;

    late final double renderedWidth;
    late final double renderedHeight;
    if (boxAspect > imageAspect) {
      renderedHeight = boxSize.height;
      renderedWidth = renderedHeight * imageAspect;
    } else {
      renderedWidth = boxSize.width;
      renderedHeight = renderedWidth / imageAspect;
    }

    final left = (boxSize.width - renderedWidth) / 2;
    final top = (boxSize.height - renderedHeight) / 2;
    final xInImage = localPosition.dx - left;
    final yInImage = localPosition.dy - top;

    if (xInImage < 0 ||
        yInImage < 0 ||
        xInImage > renderedWidth ||
        yInImage > renderedHeight) {
      return null;
    }

    final deviceX = (xInImage / renderedWidth * imageSize.width).round();
    final deviceY = (yInImage / renderedHeight * imageSize.height).round();
    return Offset(deviceX.toDouble(), deviceY.toDouble());
  }

  Future<void> _tapPreview(
    Offset localPosition,
    BoxConstraints constraints,
  ) async {
    final devicePoint = _mapPreviewPoint(localPosition, constraints);
    if (devicePoint == null) return;

    final provider = Provider.of<AppProvider>(context, listen: false);
    await provider.tapScreen(devicePoint.dx.round(), devicePoint.dy.round());
  }

  Future<void> _swipePreview(BoxConstraints constraints) async {
    final start = _panStart;
    final end = _panLast;
    _panStart = null;
    _panLast = null;
    if (start == null || end == null) return;
    if ((end - start).distance < 12) {
      if (mounted) {
        setState(() => _visualDragOffset = Offset.zero);
      }
      return;
    }

    final deviceStart = _mapPreviewPoint(start, constraints);
    final deviceEnd = _mapPreviewPoint(end, constraints);
    if (deviceStart == null || deviceEnd == null) {
      if (mounted) {
        setState(() => _visualDragOffset = Offset.zero);
      }
      return;
    }

    final provider = Provider.of<AppProvider>(context, listen: false);
    final ok = await provider.swipeScreen(
      deviceStart.dx.round(),
      deviceStart.dy.round(),
      deviceEnd.dx.round(),
      deviceEnd.dy.round(),
    );
    if (!ok && mounted) {
      setState(() => _visualDragOffset = Offset.zero);
    }
  }

  Future<void> _scrollPreview(
    Offset visualDelta,
    BoxConstraints constraints,
  ) async {
    if (_currentImage == null || _imageSize == null) return;

    final distance = visualDelta.distance;
    if (distance < 1) return;

    final startLocal = Offset(
      constraints.maxWidth / 2,
      constraints.maxHeight / 2,
    );
    final maxDrag = Size(constraints.maxWidth, constraints.maxHeight)
            .shortestSide *
        0.45;
    final clampedDelta = distance > maxDrag
        ? visualDelta / distance * maxDrag
        : visualDelta;
    final endLocal = startLocal + clampedDelta;
    final deviceStart = _mapPreviewPoint(startLocal, constraints);
    final deviceEnd = _mapPreviewPoint(endLocal, constraints);
    if (deviceStart == null || deviceEnd == null) return;

    setState(() => _visualDragOffset += clampedDelta);

    final provider = Provider.of<AppProvider>(context, listen: false);
    final ok = await provider.swipeScreen(
      deviceStart.dx.round(),
      deviceStart.dy.round(),
      deviceEnd.dx.round(),
      deviceEnd.dy.round(),
      durationMs: 220,
    );
    if (!ok && mounted) {
      setState(() => _visualDragOffset = Offset.zero);
    }
  }

  void _handlePointerSignal(
    PointerSignalEvent event,
    BoxConstraints constraints,
  ) {
    if (event is! PointerScrollEvent) return;
    final scroll = event.scrollDelta;
    final visualDelta = Offset(-scroll.dx, -scroll.dy);
    _scrollPreview(visualDelta, constraints);
  }

  void _handleKeyEvent(
    KeyEvent event,
    BoxConstraints constraints,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;

    const step = 130.0;
    Offset? delta;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      delta = const Offset(0, step);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      delta = const Offset(0, -step);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      delta = const Offset(step, 0);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      delta = const Offset(-step, 0);
    }

    if (delta != null) {
      _scrollPreview(delta, constraints);
    }
  }

  Future<void> _press(Future<bool> Function() action) async {
    await action();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableDialog(
      width: 800,
      height: 600,
      title: const Text(
        "Remote Screen View",
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Expanded(child: _buildPreview()),
            const SizedBox(height: 5),
            _buildNavigationControls(),
            const SizedBox(height: 5),
            const Text(
              "Low-framerate preview. Click to tap, drag/wheel/arrows to scroll.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return KeyboardListener(
          focusNode: _focusNode,
          onKeyEvent: (event) => _handleKeyEvent(event, constraints),
          child: Listener(
            onPointerSignal: (event) => _handlePointerSignal(event, constraints),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                _focusNode.requestFocus();
                _tapPreview(details.localPosition, constraints);
              },
              onPanStart: (details) {
                _panStart = details.localPosition;
                _panLast = details.localPosition;
                _focusNode.requestFocus();
                setState(() => _visualDragOffset = Offset.zero);
              },
              onPanUpdate: (details) {
                _panLast = details.localPosition;
                final start = _panStart;
                if (start != null) {
                  setState(() {
                    _visualDragOffset = details.localPosition - start;
                  });
                }
              },
              onPanEnd: (_) => _swipePreview(constraints),
              onPanCancel: () {
                _panStart = null;
                _panLast = null;
                setState(() => _visualDragOffset = Offset.zero);
              },
              child: ClipRect(
                child: SizedBox.expand(
                  child: Center(
                    child: _currentImage != null
                        ? Transform.translate(
                            offset: _visualDragOffset,
                            child: Image.memory(
                              _currentImage!,
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              gaplessPlayback: true,
                              fit: BoxFit.contain,
                            ),
                          )
                        : (_isLoading
                            ? const CircularProgressIndicator()
                            : const Text("No Signal")),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavigationControls() {
    return Consumer<AppProvider>(
      builder: (context, provider, _) => Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => _press(provider.pressBack),
            icon: const Icon(Icons.arrow_back),
            label: const Text("Back"),
          ),
          OutlinedButton.icon(
            onPressed: () => _press(provider.pressHome),
            icon: const Icon(Icons.home),
            label: const Text("Home"),
          ),
          OutlinedButton.icon(
            onPressed: () => _press(provider.pressRecents),
            icon: const Icon(Icons.crop_square),
            label: const Text("Recents"),
          ),
        ],
      ),
    );
  }
}
