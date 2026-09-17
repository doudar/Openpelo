import 'package:flutter/services.dart';

/// Maps the contained video rectangle; letterbox clicks are ignored.
Offset? mapScreenPoint(
  Offset point,
  Size viewport,
  Size video, {
  bool clamp = false,
}) {
  if (viewport.isEmpty || video.isEmpty) return null;
  final scale =
      (viewport.width / video.width) < (viewport.height / video.height)
      ? viewport.width / video.width
      : viewport.height / video.height;
  final left = (viewport.width - video.width * scale) / 2;
  final top = (viewport.height - video.height * scale) / 2;
  final x = (point.dx - left) / scale;
  final y = (point.dy - top) / scale;
  if (!clamp && (x < 0 || y < 0 || x >= video.width || y >= video.height)) {
    return null;
  }
  return Offset(
    x.clamp(0, video.width - 1).toDouble(),
    y.clamp(0, video.height - 1).toDouble(),
  );
}

int? androidKeycode(LogicalKeyboardKey key) {
  final keys = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.enter: 66,
    LogicalKeyboardKey.numpadEnter: 66,
    LogicalKeyboardKey.backspace: 67,
    LogicalKeyboardKey.delete: 112,
    LogicalKeyboardKey.tab: 61,
    LogicalKeyboardKey.escape: 4,
    LogicalKeyboardKey.arrowUp: 19,
    LogicalKeyboardKey.arrowDown: 20,
    LogicalKeyboardKey.arrowLeft: 21,
    LogicalKeyboardKey.arrowRight: 22,
    LogicalKeyboardKey.home: 122,
    LogicalKeyboardKey.end: 123,
    LogicalKeyboardKey.pageUp: 92,
    LogicalKeyboardKey.pageDown: 93,
  };
  return keys[key];
}
