import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/services/screen_input.dart';

void main() {
  test(
    'landscape screen maps contained coordinates and ignores letterboxing',
    () {
      const viewport = Size(1000, 1000);
      const video = Size(1920, 1080);
      expect(
        mapScreenPoint(const Offset(500, 500), viewport, video),
        const Offset(960, 540),
      );
      expect(mapScreenPoint(const Offset(500, 100), viewport, video), isNull);
      expect(mapScreenPoint(const Offset(500, 900), viewport, video), isNull);
      expect(
        mapScreenPoint(const Offset(1100, 900), viewport, video, clamp: true),
        const Offset(1919, 1079),
      );
    },
  );

  test('portrait screen maps after rotation and clamps a dragged release', () {
    const viewport = Size(1000, 600);
    const video = Size(600, 1200);
    expect(mapScreenPoint(const Offset(350, 0), viewport, video), Offset.zero);
    expect(
      mapScreenPoint(const Offset(649, 599), viewport, video),
      const Offset(598, 1198),
    );
    expect(mapScreenPoint(const Offset(100, 300), viewport, video), isNull);
    expect(
      mapScreenPoint(const Offset(100, 700), viewport, video, clamp: true),
      const Offset(0, 1199),
    );
    expect(mapScreenPoint(Offset.zero, Size.zero, video), isNull);
  });

  test(
    'navigation keys map to Android while printable text stays separate',
    () {
      expect(androidKeycode(LogicalKeyboardKey.escape), 4);
      expect(androidKeycode(LogicalKeyboardKey.enter), 66);
      expect(androidKeycode(LogicalKeyboardKey.backspace), 67);
      expect(androidKeycode(LogicalKeyboardKey.keyA), isNull);
    },
  );
}
