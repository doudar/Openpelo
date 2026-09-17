import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/apk_metadata.dart';
import 'apk_manifest_reader.dart';

typedef ApkReadRange = Future<Uint8List> Function(int start, int length);

/// Reads only the ZIP directory and AndroidManifest.xml. ZIP64 and split APKs
/// are deliberately unsupported; callers must treat that as unknown metadata.
Future<ApkMetadata> readApkMetadata(ApkReadRange read, int fileLength) async {
  if (fileLength < 22) throw const FormatException('APK is too short');
  const maxDirectory = 8 * 1024 * 1024;
  const maxManifest = 4 * 1024 * 1024;
  final tailLength = fileLength < 65557 ? fileLength : 65557;
  final tail = await read(fileLength - tailLength, tailLength);
  final tailView = ByteData.sublistView(tail);
  int? eocd;
  for (var i = tail.length - 22; i >= 0; i--) {
    if (_u32(tailView, i) == 0x06054b50 &&
        i + 22 + _u16(tailView, i + 20) == tail.length) {
      eocd = i;
      break;
    }
  }
  if (eocd == null) throw const FormatException('ZIP directory not found');
  if (_u16(tailView, eocd + 4) != 0 ||
      _u16(tailView, eocd + 6) != 0 ||
      _u16(tailView, eocd + 8) != _u16(tailView, eocd + 10)) {
    throw const FormatException('Multi-disk APK is unsupported');
  }
  final count = _u16(tailView, eocd + 10);
  final directorySize = _u32(tailView, eocd + 12);
  final directoryOffset = _u32(tailView, eocd + 16);
  if (count == 0xffff ||
      directorySize == 0xffffffff ||
      directoryOffset == 0xffffffff) {
    throw const FormatException('ZIP64 APK is unsupported');
  }
  if (directorySize > maxDirectory ||
      directoryOffset + directorySize > fileLength - tailLength + eocd) {
    throw const FormatException('Invalid or oversized ZIP directory');
  }
  final bytes = await read(directoryOffset, directorySize);
  final view = ByteData.sublistView(bytes);
  _ZipEntry? manifest;
  final abis = <String>{};
  var cursor = 0;
  for (var i = 0; i < count; i++) {
    if (cursor + 46 > bytes.length || _u32(view, cursor) != 0x02014b50) {
      throw const FormatException('Invalid ZIP central directory');
    }
    final method = _u16(view, cursor + 10);
    final flags = _u16(view, cursor + 8);
    final crc32 = _u32(view, cursor + 16);
    final compressed = _u32(view, cursor + 20);
    final uncompressed = _u32(view, cursor + 24);
    final nameLength = _u16(view, cursor + 28);
    final extraLength = _u16(view, cursor + 30);
    final commentLength = _u16(view, cursor + 32);
    final localOffset = _u32(view, cursor + 42);
    final end = cursor + 46 + nameLength + extraLength + commentLength;
    if (end > bytes.length) {
      throw const FormatException('Truncated ZIP directory entry');
    }
    final name = utf8.decode(
      bytes.sublist(cursor + 46, cursor + 46 + nameLength),
      allowMalformed: true,
    );
    if (name == 'AndroidManifest.xml') {
      if (manifest != null) {
        throw const FormatException('Duplicate Android manifest');
      }
      if ((flags & 1) != 0) {
        throw const FormatException('Encrypted Android manifest');
      }
      manifest = _ZipEntry(
        method,
        compressed,
        uncompressed,
        localOffset,
        crc32,
      );
    } else if (name.startsWith('lib/') && name.endsWith('.so')) {
      final components = name.split('/');
      if (components.length == 3 &&
          components[1].isNotEmpty &&
          components[2].isNotEmpty) {
        abis.add(components[1]);
      }
    }
    cursor = end;
  }
  if (manifest == null) {
    throw const FormatException('Android manifest not found');
  }
  if (manifest.compressed > maxManifest ||
      manifest.uncompressed > maxManifest ||
      manifest.localOffset + 30 > fileLength) {
    throw const FormatException('Android manifest exceeds inspection limits');
  }
  final local = await read(manifest.localOffset, 30);
  final localView = ByteData.sublistView(local);
  if (_u32(localView, 0) != 0x04034b50 ||
      _u16(localView, 8) != manifest.method ||
      (_u16(localView, 6) & 1) != 0) {
    throw const FormatException('Invalid local ZIP entry');
  }
  final localNameLength = _u16(localView, 26);
  final localName = await read(manifest.localOffset + 30, localNameLength);
  if (utf8.decode(localName, allowMalformed: true) != 'AndroidManifest.xml') {
    throw const FormatException('Manifest ZIP entry names disagree');
  }
  final start =
      manifest.localOffset + 30 + localNameLength + _u16(localView, 28);
  if (start + manifest.compressed > fileLength) {
    throw const FormatException('Truncated Android manifest');
  }
  final compressed = await read(start, manifest.compressed);
  late Uint8List xml;
  if (manifest.method == 0) {
    xml = compressed;
  } else if (manifest.method == 8) {
    final output = _LimitedSink(maxManifest);
    final decoder = ZLibDecoder(raw: true).startChunkedConversion(output);
    decoder.add(compressed);
    decoder.close();
    xml = Uint8List.fromList(output.bytes);
  } else {
    throw const FormatException('Unsupported manifest compression');
  }
  if (xml.length != manifest.uncompressed) {
    throw const FormatException('Android manifest length mismatch');
  }
  if (_crc32(xml) != manifest.crc32) {
    throw const FormatException('Android manifest checksum mismatch');
  }
  final manifestInfo = readAndroidManifest(xml);
  return ApkMetadata(
    minSdk: manifestInfo.minSdk,
    nativeAbis: abis.toList()..sort(),
    packageId: manifestInfo.packageId,
    versionName: manifestInfo.versionName,
  );
}

int _u16(ByteData data, int offset) => data.getUint16(offset, Endian.little);
int _u32(ByteData data, int offset) => data.getUint32(offset, Endian.little);

class _ZipEntry {
  final int method;
  final int compressed;
  final int uncompressed;
  final int localOffset;
  final int crc32;
  const _ZipEntry(
    this.method,
    this.compressed,
    this.uncompressed,
    this.localOffset,
    this.crc32,
  );
}

int _crc32(Uint8List bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

class _LimitedSink implements Sink<List<int>> {
  final int limit;
  final bytes = <int>[];
  _LimitedSink(this.limit);

  @override
  void add(List<int> data) {
    if (bytes.length + data.length > limit) {
      throw const FormatException('Inflated manifest exceeds inspection limit');
    }
    bytes.addAll(data);
  }

  @override
  void close() {}
}
