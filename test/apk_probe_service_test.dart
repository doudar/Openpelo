import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openpelo/models/apk_metadata.dart';
import 'package:openpelo/services/apk_probe_service.dart';
import 'package:openpelo/services/apk_archive_reader.dart';

void main() {
  final apk = _apk(_manifest(24), nativeAbi: 'arm64-v8a');

  test('reads API and actual native libraries using bounded ranges', () async {
    final ranges = <String>[];
    final client = MockClient((request) async {
      final range = request.headers['Range']!;
      ranges.add(range);
      final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(range)!;
      final start = int.parse(match.group(1)!);
      final end = int.parse(match.group(2)!);
      return http.Response.bytes(
        apk.sublist(start, end + 1),
        206,
        headers: {
          'content-range': 'bytes $start-$end/${apk.length}',
          'etag': '"revision-1"',
        },
      );
    });
    final service = ApkProbeService(client: client);
    final result = await service.probe(
      Uri.parse('https://example.org/app.apk'),
    );
    expect(result.metadata.minSdk, 24);
    expect(result.metadata.packageId, 'org.example.app');
    expect(result.metadata.versionName, '1.2.3');
    expect(result.metadata.nativeAbis, ['arm64-v8a']);
    expect(result.metadata.supportsDevice(24, ['arm64-v8a']), isTrue);
    expect(result.metadata.supportsDevice(23, ['arm64-v8a']), isFalse);
    expect(result.metadata.supportsDevice(24, ['armeabi-v7a']), isFalse);
    expect(ranges.first, 'bytes=0-0');
    expect(ranges.every((range) => range.startsWith('bytes=')), isTrue);
    expect(ApkProbeResult.fromJson(result.toJson()).metadata.nativeAbis, [
      'arm64-v8a',
    ]);
  });

  test('no native libraries means universal architecture', () async {
    final universal = _apk(_manifest(21), deflateManifest: true);
    final file = File(
      '${Directory.systemTemp.path}/openpelo-probe-${DateTime.now().microsecondsSinceEpoch}.apk',
    );
    try {
      await file.writeAsBytes(universal);
      final metadata = await ApkProbeService().inspectFile(file);
      expect(metadata.nativeAbis, isEmpty);
      expect(metadata.supportsDevice(24, ['armeabi-v7a']), isTrue);
      expect(metadata.supportsDevice(20, ['arm64-v8a']), isFalse);
      expect(ApkMetadata.fromJson(metadata.toJson()).minSdk, 21);
    } finally {
      if (await file.exists()) await file.delete();
    }
  });

  test('uses a conditional validator to reuse prior metadata', () async {
    final previous = ApkProbeResult(
      metadata: ApkMetadata(minSdk: 21, nativeAbis: []),
      etag: '"revision-1"',
      contentLength: apk.length,
      resolvedUrl: 'https://example.org/app.apk',
    );
    final client = MockClient((request) async {
      expect(request.method, 'HEAD');
      expect(request.headers['If-None-Match'], '"revision-1"');
      return http.Response('', 304);
    });
    final result = await ApkProbeService(
      client: client,
    ).probe(Uri.parse('https://example.org/app.apk'), previous: previous);
    expect(identical(result, previous), isTrue);
  });

  test('rejects a host that ignores Range', () async {
    final client = MockClient((_) async => http.Response.bytes(apk, 200));
    expect(
      ApkProbeService(
        client: client,
      ).probe(Uri.parse('https://example.org/a.apk')),
      throwsA(isA<ApkProbeException>()),
    );
  });

  test('rejects a resource that changes between ranges', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      final match = RegExp(
        r'^bytes=(\d+)-(\d+)$',
      ).firstMatch(request.headers['Range']!)!;
      final start = int.parse(match.group(1)!);
      final end = int.parse(match.group(2)!);
      return http.Response.bytes(
        apk.sublist(start, end + 1),
        206,
        headers: {
          'content-range': 'bytes $start-$end/${apk.length}',
          'etag': calls == 1 ? '"revision-1"' : '"revision-2"',
        },
      );
    });
    expect(
      ApkProbeService(
        client: client,
      ).probe(Uri.parse('https://example.org/a.apk')),
      throwsA(isA<ApkProbeException>()),
    );
  });

  test('reads deflated UTF-16 manifest and default minimum API', () async {
    final bytes = _apk(_manifest(null, utf8Pool: false), deflateManifest: true);
    final metadata = await readApkMetadata(
      (start, length) async => bytes.sublist(start, start + length),
      bytes.length,
    );
    expect(metadata.minSdk, 1);
    expect(metadata.packageId, 'org.example.app');
  });

  test(
    'rejects split APK rather than reporting universal compatibility',
    () async {
      final bytes = _apk(_manifest(24, split: true));
      expect(
        readApkMetadata(
          (start, length) async => bytes.sublist(start, start + length),
          bytes.length,
        ),
        throwsFormatException,
      );
    },
  );

  test('rejects an oversized streamed range', () async {
    final client = StreamingClient(
      (request) async => http.StreamedResponse(
        Stream.value([0, 1]),
        206,
        headers: {'content-range': 'bytes 0-0/100000'},
      ),
    );
    expect(
      ApkProbeService(
        client: client,
      ).probe(Uri.parse('https://example.org/app.apk')),
      throwsA(isA<ApkProbeException>()),
    );
  });

  test('rejects HTTPS redirect to HTTP before requesting the target', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
        '',
        302,
        headers: {'location': 'http://example.org/app.apk'},
      );
    });
    await expectLater(
      ApkProbeService(
        client: client,
      ).probe(Uri.parse('https://example.org/app.apk')),
      throwsA(isA<ApkProbeException>()),
    );
    expect(calls, 1);
  });

  test('uses host download headers for compatibility probes', () async {
    final client = MockClient((request) async {
      expect(request.headers['User-Agent'], contains('OpenPelo'));
      expect(request.headers['Referer'], 'https://teslacoilapps.com/');
      return http.Response('', 404);
    });
    await expectLater(
      ApkProbeService(
        client: client,
      ).probe(Uri.parse('https://teslacoilapps.com/app.apk')),
      throwsA(isA<ApkProbeException>()),
    );
  });
}

class StreamingClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  StreamingClient(this.handler);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

Uint8List _manifest(int? minSdk, {bool utf8Pool = true, bool split = false}) {
  final strings = [
    'manifest',
    'package',
    'versionName',
    'uses-sdk',
    'minSdkVersion',
    'org.example.app',
    '1.2.3',
    'split',
    'config.arm64',
  ];
  final stringData = BytesBuilder();
  final offsets = <int>[];
  for (final string in strings) {
    offsets.add(stringData.length);
    final encoded = string.codeUnits;
    if (utf8Pool) {
      stringData.add([encoded.length, encoded.length, ...encoded, 0]);
    } else {
      final data = ByteData(2 + encoded.length * 2 + 2);
      _u16(data, 0, encoded.length);
      for (var i = 0; i < encoded.length; i++) {
        _u16(data, 2 + i * 2, encoded[i]);
      }
      stringData.add(data.buffer.asUint8List());
    }
  }
  final poolHeader = ByteData(28 + strings.length * 4);
  _u16(poolHeader, 0, 0x0001);
  _u16(poolHeader, 2, 28);
  _u32(poolHeader, 4, poolHeader.lengthInBytes + stringData.length);
  _u32(poolHeader, 8, strings.length);
  _u32(poolHeader, 16, utf8Pool ? 0x100 : 0);
  _u32(poolHeader, 20, poolHeader.lengthInBytes);
  for (var i = 0; i < offsets.length; i++) {
    _u32(poolHeader, 28 + i * 4, offsets[i]);
  }
  final pool = BytesBuilder()
    ..add(poolHeader.buffer.asUint8List())
    ..add(stringData.takeBytes());
  final root = _element(0, [
    _attribute(1, raw: 5),
    _attribute(2, raw: 6),
    if (split) _attribute(7, raw: 8),
  ]);
  final sdk = minSdk == null
      ? Uint8List(0)
      : _element(3, [_attribute(4, integer: minSdk)]);
  final result = BytesBuilder();
  final xmlHeader = ByteData(8);
  _u16(xmlHeader, 0, 0x0003);
  _u16(xmlHeader, 2, 8);
  _u32(xmlHeader, 4, 8 + pool.length + root.length + sdk.length);
  result.add(xmlHeader.buffer.asUint8List());
  result.add(pool.takeBytes());
  result.add(root);
  result.add(sdk);
  return result.takeBytes();
}

Uint8List _element(int name, List<Uint8List> attributes) {
  final data = ByteData(36 + attributes.length * 20);
  _u16(data, 0, 0x0102);
  _u16(data, 2, 16);
  _u32(data, 4, data.lengthInBytes);
  _u32(data, 12, 0xffffffff);
  _u32(data, 16, 0xffffffff);
  _u32(data, 20, name);
  _u16(data, 24, 20);
  _u16(data, 26, 20);
  _u16(data, 28, attributes.length);
  final bytes = data.buffer.asUint8List();
  for (var i = 0; i < attributes.length; i++) {
    bytes.setRange(36 + i * 20, 56 + i * 20, attributes[i]);
  }
  return bytes;
}

Uint8List _attribute(int name, {int? raw, int? integer}) {
  final data = ByteData(20);
  _u32(data, 0, 0xffffffff);
  _u32(data, 4, name);
  _u32(data, 8, raw ?? 0xffffffff);
  _u16(data, 12, 8);
  data.setUint8(15, integer == null ? 0x03 : 0x10);
  _u32(data, 16, integer ?? raw!);
  return data.buffer.asUint8List();
}

Uint8List _apk(
  Uint8List manifest, {
  String? nativeAbi,
  bool deflateManifest = false,
}) {
  final entries = <(String, Uint8List, int, int, int)>[
    (
      'AndroidManifest.xml',
      deflateManifest
          ? Uint8List.fromList(ZLibEncoder(raw: true).convert(manifest))
          : manifest,
      deflateManifest ? 8 : 0,
      manifest.length,
      _crc32(manifest),
    ),
    if (nativeAbi != null)
      (
        'lib/$nativeAbi/libexample.so',
        Uint8List.fromList([1]),
        0,
        1,
        _crc32(Uint8List.fromList([1])),
      ),
  ];
  final body = BytesBuilder();
  final directory = BytesBuilder();
  for (final (name, content, method, uncompressedLength, crc32) in entries) {
    final nameBytes = Uint8List.fromList(name.codeUnits);
    final localOffset = body.length;
    final local = ByteData(30);
    _u32(local, 0, 0x04034b50);
    _u16(local, 4, 20);
    _u16(local, 8, method);
    _u32(local, 14, crc32);
    _u32(local, 18, content.length);
    _u32(local, 22, uncompressedLength);
    _u16(local, 26, nameBytes.length);
    body.add(local.buffer.asUint8List());
    body.add(nameBytes);
    body.add(content);
    final central = ByteData(46);
    _u32(central, 0, 0x02014b50);
    _u16(central, 4, 20);
    _u16(central, 6, 20);
    _u16(central, 10, method);
    _u32(central, 16, crc32);
    _u32(central, 20, content.length);
    _u32(central, 24, uncompressedLength);
    _u16(central, 28, nameBytes.length);
    _u32(central, 42, localOffset);
    directory.add(central.buffer.asUint8List());
    directory.add(nameBytes);
  }
  final directoryOffset = body.length;
  final directorySize = directory.length;
  body.add(directory.takeBytes());
  final eocd = ByteData(22);
  _u32(eocd, 0, 0x06054b50);
  _u16(eocd, 8, entries.length);
  _u16(eocd, 10, entries.length);
  _u32(eocd, 12, directorySize);
  _u32(eocd, 16, directoryOffset);
  body.add(eocd.buffer.asUint8List());
  return body.takeBytes();
}

void _u16(ByteData data, int offset, int value) =>
    data.setUint16(offset, value, Endian.little);
void _u32(ByteData data, int offset, int value) =>
    data.setUint32(offset, value, Endian.little);

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
