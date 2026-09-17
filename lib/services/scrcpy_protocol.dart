import 'dart:convert';
import 'dart:typed_data';

/// The wire format implemented by scrcpy server v3.3.4. All integers are big
/// endian; see app/src/control_msg.c and server device/Streamer.java upstream.
class ScrcpyProtocol {
  static const int maxPacketSize = 4 * 1024 * 1024;
  static const int codecH264 = 0x68323634; // h264
  static const int configFlag = 1 << 63;
  static const int keyFrameFlag = 1 << 62;
  static const int timestampMask = (1 << 62) - 1;

  static ScrcpyVideoHeader parseVideoHeader(Uint8List bytes) {
    if (bytes.length != 12) throw const FormatException('Invalid video header');
    final data = ByteData.sublistView(bytes);
    final codec = data.getUint32(0);
    if (codec != codecH264) {
      throw FormatException('Unsupported scrcpy video codec: $codec');
    }
    final width = data.getUint32(4);
    final height = data.getUint32(8);
    if (width == 0 || height == 0 || width > 16384 || height > 16384) {
      throw FormatException(
        'Invalid scrcpy video dimensions: $width x $height',
      );
    }
    return ScrcpyVideoHeader(width, height);
  }

  static ScrcpyFrameHeader parseFrameHeader(Uint8List bytes) {
    if (bytes.length != 12) throw const FormatException('Invalid frame header');
    final data = ByteData.sublistView(bytes);
    final flagsAndPts = data.getUint64(0);
    final size = data.getUint32(8);
    if (size == 0 || size > maxPacketSize) {
      throw FormatException('Invalid scrcpy packet size: $size');
    }
    final isConfig = flagsAndPts & configFlag != 0;
    return ScrcpyFrameHeader(
      size: size,
      timestampUs: isConfig ? 0 : flagsAndPts & timestampMask,
      isConfig: isConfig,
      isKeyFrame: !isConfig && flagsAndPts & keyFrameFlag != 0,
    );
  }

  static Uint8List keycode({
    required int keycode,
    required int action,
    int repeat = 0,
    int metaState = 0,
  }) {
    final bytes = Uint8List(14);
    final data = ByteData.sublistView(bytes);
    data.setUint8(0, 0);
    data.setUint8(1, action);
    data.setUint32(2, keycode);
    data.setUint32(6, repeat);
    data.setUint32(10, metaState);
    return bytes;
  }

  static Uint8List text(String value) {
    final encoded = utf8.encode(value);
    if (encoded.length > 300) {
      throw ArgumentError('Text exceeds 300 UTF-8 bytes');
    }
    final bytes = Uint8List(5 + encoded.length);
    final data = ByteData.sublistView(bytes);
    data.setUint8(0, 1);
    data.setUint32(1, encoded.length);
    bytes.setRange(5, bytes.length, encoded);
    return bytes;
  }

  static Uint8List touch({
    required int action,
    required int x,
    required int y,
    required int width,
    required int height,
    double pressure = 1,
    int pointerId = -2,
    int actionButton = 0,
    int buttons = 0,
  }) {
    _checkPosition(x, y, width, height);
    if (pressure < 0 || pressure > 1) throw RangeError.range(pressure, 0, 1);
    final bytes = Uint8List(32);
    final data = ByteData.sublistView(bytes);
    data.setUint8(0, 2);
    data.setUint8(1, action);
    data.setUint64(2, pointerId & 0xffffffffffffffff);
    _writePosition(data, 10, x, y, width, height);
    data.setUint16(22, (pressure * 65535).round());
    data.setUint32(24, actionButton);
    data.setUint32(28, buttons);
    return bytes;
  }

  static Uint8List scroll({
    required int x,
    required int y,
    required int width,
    required int height,
    double horizontal = 0,
    double vertical = 0,
    int buttons = 0,
  }) {
    _checkPosition(x, y, width, height);
    final bytes = Uint8List(21);
    final data = ByteData.sublistView(bytes);
    data.setUint8(0, 3);
    _writePosition(data, 1, x, y, width, height);
    data.setInt16(13, _scrollFixed(horizontal));
    data.setInt16(15, _scrollFixed(vertical));
    data.setUint32(17, buttons);
    return bytes;
  }

  static Uint8List backOrScreenOn(int action) =>
      Uint8List.fromList([4, action]);

  static void _writePosition(
    ByteData data,
    int offset,
    int x,
    int y,
    int width,
    int height,
  ) {
    data.setInt32(offset, x);
    data.setInt32(offset + 4, y);
    data.setUint16(offset + 8, width);
    data.setUint16(offset + 10, height);
  }

  static void _checkPosition(int x, int y, int width, int height) {
    if (width <= 0 ||
        height <= 0 ||
        width > 65535 ||
        height > 65535 ||
        x < 0 ||
        x >= width ||
        y < 0 ||
        y >= height) {
      throw RangeError(
        'Position outside scrcpy video: $x,$y in $width x $height',
      );
    }
  }

  static int _scrollFixed(double value) {
    // scrcpy normalizes [-16, 16] to [-1, 1], multiplies by 2^15,
    // truncates toward zero, then saturates +1 to 0x7fff.
    final scaled = (value.clamp(-16.0, 16.0) / 16.0 * 32768).truncate();
    return scaled.clamp(-32768, 32767);
  }
}

class ScrcpyVideoHeader {
  final int width;
  final int height;
  const ScrcpyVideoHeader(this.width, this.height);
}

class ScrcpyFrameHeader {
  final int size;
  final int timestampUs;
  final bool isConfig;
  final bool isKeyFrame;
  const ScrcpyFrameHeader({
    required this.size,
    required this.timestampUs,
    required this.isConfig,
    required this.isKeyFrame,
  });
}

class ScrcpyVideoPacket {
  final Uint8List bytes;
  final int timestampUs;
  final bool isConfig;
  final bool isKeyFrame;
  const ScrcpyVideoPacket({
    required this.bytes,
    required this.timestampUs,
    required this.isConfig,
    required this.isKeyFrame,
  });
}

enum ScrcpyTouchAction {
  down(0),
  up(1),
  move(2),
  cancel(3);

  final int value;
  const ScrcpyTouchAction(this.value);
}

enum ScrcpyKeyAction {
  down(0),
  up(1);

  final int value;
  const ScrcpyKeyAction(this.value);
}
