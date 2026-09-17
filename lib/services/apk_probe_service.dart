import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/apk_metadata.dart';
import 'apk_archive_reader.dart';
import 'apk_probe_transport.dart';

class ApkProbeException implements Exception {
  final String message;
  const ApkProbeException(this.message);
  @override
  String toString() => 'ApkProbeException: $message';
}

class ApkProbeResult {
  final ApkMetadata metadata;
  final String? etag;
  final String? lastModified;
  final int contentLength;
  final String resolvedUrl;

  const ApkProbeResult({
    required this.metadata,
    required this.contentLength,
    required this.resolvedUrl,
    this.etag,
    this.lastModified,
  });

  Map<String, dynamic> toJson() => {
    'metadata': metadata.toJson(),
    'contentLength': contentLength,
    'resolvedUrl': resolvedUrl,
    if (etag != null) 'etag': etag,
    if (lastModified != null) 'lastModified': lastModified,
  };

  factory ApkProbeResult.fromJson(Map<String, dynamic> json) => ApkProbeResult(
    metadata: ApkMetadata.fromJson(
      (json['metadata'] as Map).cast<String, dynamic>(),
    ),
    contentLength: json['contentLength'] as int,
    resolvedUrl: json['resolvedUrl'] as String,
    etag: json['etag'] as String?,
    lastModified: json['lastModified'] as String?,
  );
}

/// Inspects remote APK metadata using bounded HTTP byte ranges (a very small
/// APK may fit entirely in the ZIP footer range). The caller owns caching and
/// should retain a
/// previous result only if it has an ETag or Last-Modified validator. Without
/// a validator, ranges are a best effort snapshot: a same-length change
/// between requests cannot be detected remotely. Recheck the downloaded file.
class ApkProbeService {
  static const _timeout = Duration(seconds: 15);
  static const _maxFileLength = 0xffffffff;
  final http.Client _client;
  final bool _ownsClient;

  ApkProbeService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<ApkProbeResult> probe(Uri uri, {ApkProbeResult? previous}) async {
    if (uri.scheme != 'https') {
      throw const ApkProbeException('APK URL must use HTTPS');
    }
    if (previous != null && _hasValidator(previous)) {
      final headers = <String, String>{};
      if (_isStrongEtag(previous.etag)) {
        headers['If-None-Match'] = previous.etag!;
      } else if (previous.lastModified != null) {
        headers['If-Modified-Since'] = previous.lastModified!;
      }
      try {
        final check = await _request('HEAD', uri, headers);
        final status = check.response.statusCode;
        if (status == 304) {
          await _discard(check.response);
          return previous;
        }
        if (status == 200 &&
            _isStrongEtag(previous.etag) &&
            check.response.headers['etag'] == previous.etag &&
            int.tryParse(check.response.headers['content-length'] ?? '') ==
                previous.contentLength) {
          await _discard(check.response);
          return previous;
        }
        await _discard(check.response);
      } on TimeoutException {
        // The range request below can still succeed on hosts without HEAD.
      }
    }

    final first = await _fetchRange(uri, 0, 1);
    final total = first.total;
    final etag = first.etag;
    final lastModified = first.lastModified;
    Future<Uint8List> read(int start, int length) async {
      if (start == 0 && length == 1) return first.bytes;
      final part = await _fetchRange(
        uri,
        start,
        length,
        expectedTotal: total,
        etag: etag,
        lastModified: lastModified,
      );
      return part.bytes;
    }

    final metadata = await readApkMetadata(read, total);
    return ApkProbeResult(
      metadata: metadata,
      etag: etag,
      lastModified: lastModified,
      contentLength: total,
      resolvedUrl: first.uri.toString(),
    );
  }

  /// Rechecks a downloaded or user-selected APK without loading it into RAM.
  Future<ApkMetadata> inspectFile(File file) async {
    final handle = await file.open();
    try {
      final length = await handle.length();
      if (length > _maxFileLength) {
        throw const ApkProbeException('APK exceeds ZIP inspection limit');
      }
      return await readApkMetadata((start, count) async {
        if (start < 0 || count < 0 || start + count > length) {
          throw const FormatException('APK range is outside the file');
        }
        await handle.setPosition(start);
        final data = await handle.read(count);
        if (data.length != count) {
          throw const FormatException('APK changed during inspection');
        }
        return Uint8List.fromList(data);
      }, length);
    } finally {
      await handle.close();
    }
  }

  Future<_Range> _fetchRange(
    Uri uri,
    int start,
    int length, {
    int? expectedTotal,
    String? etag,
    String? lastModified,
  }) async {
    if (start < 0 || length <= 0 || start + length > _maxFileLength) {
      throw const ApkProbeException('APK range exceeds inspection limits');
    }
    final headers = <String, String>{
      'Range': 'bytes=$start-${start + length - 1}',
      'Accept-Encoding': 'identity',
    };
    if (_isStrongEtag(etag)) {
      headers['If-Range'] = etag!;
    } else if (lastModified != null) {
      headers['If-Range'] = lastModified;
    }
    final reply = await _request('GET', uri, headers);
    final response = reply.response;
    if (response.statusCode != 206) {
      await _discard(response);
      throw ApkProbeException(
        response.statusCode == 200
            ? 'Server ignored HTTP Range; APK cannot be inspected without downloading it'
            : 'APK range request failed: HTTP ${response.statusCode}',
      );
    }
    final encoding = response.headers['content-encoding'];
    if (encoding != null && encoding.toLowerCase() != 'identity') {
      await _discard(response);
      throw const ApkProbeException('Server compressed an APK byte range');
    }
    final match = RegExp(
      r'^bytes (\d+)-(\d+)/(\d+)$',
    ).firstMatch(response.headers['content-range'] ?? '');
    if (match == null) {
      await _discard(response);
      throw const ApkProbeException(
        'Server did not provide a valid Content-Range',
      );
    }
    final actualStart = int.parse(match.group(1)!);
    final actualEnd = int.parse(match.group(2)!);
    final total = int.parse(match.group(3)!);
    if (actualStart != start ||
        actualEnd != start + length - 1 ||
        total < 22 ||
        total > _maxFileLength ||
        (expectedTotal != null && total != expectedTotal) ||
        (etag != null &&
            response.headers['etag'] != null &&
            response.headers['etag'] != etag) ||
        (lastModified != null &&
            response.headers['last-modified'] != null &&
            response.headers['last-modified'] != lastModified)) {
      await _discard(response);
      throw const ApkProbeException('APK changed or returned an invalid range');
    }
    final bytes = await _readBounded(response.stream, length);
    return _Range(
      bytes,
      total,
      response.headers['etag'],
      response.headers['last-modified'],
      reply.uri,
    );
  }

  Future<_Reply> _request(
    String method,
    Uri initial,
    Map<String, String> headers,
  ) async {
    var uri = initial;
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (uri.scheme != 'https') {
        throw const ApkProbeException('APK redirect must use HTTPS');
      }
      final request = http.Request(method, uri)
        ..followRedirects = false
        ..headers.addAll({
          'User-Agent': 'Mozilla/5.0 OpenPelo/1.0',
          'Accept': '*/*',
          'Accept-Encoding': 'identity',
          if (uri.host == 'teslacoilapps.com' ||
              uri.host.endsWith('.teslacoilapps.com'))
            'Referer': 'https://teslacoilapps.com/',
        })
        ..headers.addAll(headers);
      final response = await sendApkProbeRequest(
        _client,
        request,
      ).timeout(_timeout);
      if (response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 303 ||
          response.statusCode == 307 ||
          response.statusCode == 308) {
        final location = response.headers['location'];
        await _discard(response);
        if (location == null) {
          throw const ApkProbeException('APK redirect has no location');
        }
        uri = uri.resolve(location);
        continue;
      }
      return _Reply(response, uri);
    }
    throw const ApkProbeException('Too many APK redirects');
  }

  Future<void> _discard(http.StreamedResponse response) async {
    final subscription = response.stream.listen((_) {});
    await subscription.cancel();
  }

  Future<Uint8List> _readBounded(Stream<List<int>> stream, int length) async {
    final output = BytesBuilder(copy: false);
    final iterator = StreamIterator<List<int>>(stream);
    final deadline = DateTime.now().add(_timeout);
    try {
      while (true) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          throw TimeoutException('APK range timed out');
        }
        if (!await iterator.moveNext().timeout(remaining)) break;
        final chunk = iterator.current;
        if (output.length + chunk.length > length) {
          throw const ApkProbeException(
            'Server exceeded requested APK byte range',
          );
        }
        output.add(chunk);
      }
      if (output.length != length) {
        throw const ApkProbeException('Incomplete APK byte range');
      }
      return output.takeBytes();
    } finally {
      await iterator.cancel();
    }
  }
}

bool _isStrongEtag(String? value) =>
    value != null && value.startsWith('"') && value.endsWith('"');

bool _hasValidator(ApkProbeResult result) =>
    _isStrongEtag(result.etag) || result.lastModified != null;

class _Reply {
  final http.StreamedResponse response;
  final Uri uri;
  const _Reply(this.response, this.uri);
}

class _Range {
  final Uint8List bytes;
  final int total;
  final String? etag;
  final String? lastModified;
  final Uri uri;
  const _Range(this.bytes, this.total, this.etag, this.lastModified, this.uri);
}
