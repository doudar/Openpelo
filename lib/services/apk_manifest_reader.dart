import 'dart:convert';
import 'dart:typed_data';

class AndroidManifestInfo {
  final int minSdk;
  final String? packageId;
  final String? versionName;
  const AndroidManifestInfo(this.minSdk, this.packageId, this.versionName);
}

/// Parses the binary Android XML used in APKs. A missing uses-sdk means API 1.
AndroidManifestInfo readAndroidManifest(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 8 ||
      _u16(data, 0) != 0x0003 ||
      _u16(data, 2) != 8 ||
      _u32(data, 4) != bytes.length) {
    throw const FormatException('Unsupported Android manifest format');
  }
  var cursor = 8;
  List<String>? strings;
  int? minSdk;
  String? packageId;
  String? versionName;
  var sawManifest = false;
  while (cursor < bytes.length) {
    if (cursor + 8 > bytes.length) {
      throw const FormatException('Truncated Android XML chunk');
    }
    final type = _u16(data, cursor);
    final headerSize = _u16(data, cursor + 2);
    final size = _u32(data, cursor + 4);
    if (headerSize < 8 || size < headerSize || cursor + size > bytes.length) {
      throw const FormatException('Invalid Android XML chunk');
    }
    if (type == 0x0001) {
      strings = _readStrings(bytes, cursor, headerSize, size);
    } else if (type == 0x0102) {
      if (strings == null || headerSize < 16 || size < 36) {
        throw const FormatException('Invalid Android XML element');
      }
      final element = _string(strings, _u32(data, cursor + 20));
      if (element == 'uses-split') {
        throw const FormatException('APK requires a split package');
      }
      if (element == 'manifest') sawManifest = true;
      final attrOffset = cursor + 16 + _u16(data, cursor + 24);
      final attrSize = _u16(data, cursor + 26);
      final attrCount = _u16(data, cursor + 28);
      if (attrSize < 20 ||
          attrOffset < cursor + 36 ||
          attrOffset + attrSize * attrCount > cursor + size) {
        throw const FormatException('Invalid Android XML attributes');
      }
      for (var i = 0; i < attrCount; i++) {
        final offset = attrOffset + i * attrSize;
        final name = _string(strings, _u32(data, offset + 4));
        if ((element == 'manifest' &&
                (name == 'split' || name == 'requiredSplitTypes') &&
                (_attributeString(data, strings, offset)?.isNotEmpty ??
                    false)) ||
            (name == 'isSplitRequired' &&
                _attributeTrue(data, strings, offset))) {
          throw const FormatException('APK requires split packages');
        }
        if (element == 'manifest' && name == 'package') {
          packageId = _attributeString(data, strings, offset);
        } else if (element == 'manifest' && name == 'versionName') {
          versionName = _attributeString(data, strings, offset);
        } else if (element == 'uses-sdk' && name == 'minSdkVersion') {
          minSdk = _attributeInt(data, strings, offset);
          if (minSdk == null) {
            throw const FormatException('Unsupported minSdkVersion value');
          }
        }
      }
    }
    cursor += size;
  }
  if (cursor != bytes.length || !sawManifest) {
    throw const FormatException('Invalid Android XML length');
  }
  return AndroidManifestInfo(minSdk ?? 1, packageId, versionName);
}

List<String> _readStrings(Uint8List bytes, int start, int header, int size) {
  final data = ByteData.sublistView(bytes);
  if (header < 28) throw const FormatException('Invalid string pool');
  final count = _u32(data, start + 8);
  final flags = _u32(data, start + 16);
  final stringsStart = _u32(data, start + 20);
  if (count > 100000 ||
      header + count * 4 > size ||
      stringsStart < header + count * 4 ||
      stringsStart >= size) {
    throw const FormatException('Invalid string pool size');
  }
  final utf8Pool = (flags & 0x100) != 0;
  final strings = <String>[];
  for (var i = 0; i < count; i++) {
    final relative = _u32(data, start + header + i * 4);
    var offset = start + stringsStart + relative;
    final end = start + size;
    if (offset >= end) throw const FormatException('Invalid string offset');
    if (utf8Pool) {
      final (_, next) = _utf8Length(bytes, offset, end);
      final (byteLength, afterLength) = _utf8Length(bytes, next, end);
      offset = afterLength;
      if (offset + byteLength >= end || bytes[offset + byteLength] != 0) {
        throw const FormatException('Truncated UTF-8 string');
      }
      strings.add(utf8.decode(bytes.sublist(offset, offset + byteLength)));
    } else {
      final (units, next) = _utf16Length(data, offset, end);
      offset = next;
      if (offset + units * 2 + 2 > end || _u16(data, offset + units * 2) != 0) {
        throw const FormatException('Truncated UTF-16 string');
      }
      final codes = <int>[];
      for (var j = 0; j < units; j++) {
        codes.add(_u16(data, offset + j * 2));
      }
      strings.add(String.fromCharCodes(codes));
    }
  }
  return strings;
}

(int, int) _utf8Length(Uint8List bytes, int offset, int end) {
  if (offset >= end) throw const FormatException('Truncated string length');
  final first = bytes[offset++];
  if ((first & 0x80) == 0) return (first, offset);
  if (offset >= end) throw const FormatException('Truncated string length');
  return (((first & 0x7f) << 8) | bytes[offset], offset + 1);
}

(int, int) _utf16Length(ByteData data, int offset, int end) {
  if (offset + 2 > end) throw const FormatException('Truncated string length');
  final first = _u16(data, offset);
  offset += 2;
  if ((first & 0x8000) == 0) return (first, offset);
  if (offset + 2 > end) throw const FormatException('Truncated string length');
  return (((first & 0x7fff) << 16) | _u16(data, offset), offset + 2);
}

String _string(List<String> strings, int index) {
  if (index >= strings.length) {
    throw const FormatException('Invalid Android XML string index');
  }
  return strings[index];
}

String? _attributeString(ByteData data, List<String> strings, int offset) {
  final raw = _u32(data, offset + 8);
  if (raw != 0xffffffff) return _string(strings, raw);
  final type = data.getUint8(offset + 15);
  final value = _u32(data, offset + 16);
  if (type == 0x03) return _string(strings, value);
  if (type >= 0x10 && type <= 0x1f) return value.toString();
  return null;
}

int? _attributeInt(ByteData data, List<String> strings, int offset) {
  final type = data.getUint8(offset + 15);
  final value = _u32(data, offset + 16);
  if (type >= 0x10 && type <= 0x1f) return value;
  final raw = _attributeString(data, strings, offset);
  return raw == null ? null : int.tryParse(raw);
}

bool _attributeTrue(ByteData data, List<String> strings, int offset) {
  final type = data.getUint8(offset + 15);
  if (type == 0x12) return _u32(data, offset + 16) != 0;
  return _attributeString(data, strings, offset)?.toLowerCase() == 'true';
}

int _u16(ByteData data, int offset) => data.getUint16(offset, Endian.little);
int _u32(ByteData data, int offset) => data.getUint32(offset, Endian.little);
