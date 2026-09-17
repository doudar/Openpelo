import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Uses Windows' certificate store via curl only when Dart TLS fails. Unlike
/// the ordinary download fallback, this cancels unbounded response bodies.
Future<http.StreamedResponse> sendApkProbeRequest(
  http.Client client,
  http.Request request,
) async {
  try {
    return await client.send(request);
  } catch (error) {
    final detail = error.toString().toLowerCase();
    if (!Platform.isWindows ||
        !(error is HandshakeException ||
            detail.contains('certificate_verify_failed') ||
            detail.contains('handshakeexception'))) {
      rethrow;
    }
    return _sendWithWindowsCurl(request);
  }
}

Future<http.StreamedResponse> _sendWithWindowsCurl(http.Request request) async {
  final range = RegExp(
    r'^bytes=(\d+)-(\d+)$',
  ).firstMatch(request.headers['Range'] ?? '');
  final limit = request.method == 'HEAD'
      ? 0
      : range == null
      ? null
      : int.parse(range.group(2)!) - int.parse(range.group(1)!) + 1;
  if (limit == null || limit < 0 || limit > 8 * 1024 * 1024) {
    throw const FormatException('Probe request has no bounded byte range');
  }
  final process = await Process.start('curl.exe', [
    '--silent',
    '--show-error',
    '--include',
    '--suppress-connect-headers',
    '--proto',
    '=https',
    '--max-time',
    '15',
    '--connect-timeout',
    '10',
    if (request.method == 'HEAD') '--head',
    for (final header in request.headers.entries) ...[
      '-H',
      '${header.key}: ${header.value}',
    ],
    request.url.toString(),
  ]);
  final stderr = StringBuffer();
  final errors = process.stderr.transform(utf8.decoder).listen((chunk) {
    if (stderr.length < 4096) {
      stderr.write(
        chunk.substring(0, chunk.length.clamp(0, 4096 - stderr.length)),
      );
    }
  });
  final iterator = StreamIterator(process.stdout);
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  var buffer = <int>[];
  int? status;
  final headers = <String, String>{};
  final body = BytesBuilder(copy: false);
  try {
    while (true) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero ||
          !await iterator.moveNext().timeout(remaining)) {
        break;
      }
      final chunk = iterator.current;
      if (status == null) {
        buffer.addAll(chunk);
        final headerEnd = _headerEnd(buffer);
        if (headerEnd < 0) {
          if (buffer.length > 65536) {
            throw const FormatException('Oversized HTTP headers');
          }
          continue;
        }
        if (headerEnd > 65536) {
          throw const FormatException('Oversized HTTP headers');
        }
        final lines = latin1.decode(buffer.sublist(0, headerEnd)).split('\r\n');
        final match = RegExp(r'^HTTP/\S+ (\d{3})').firstMatch(lines.first);
        if (match == null) throw const FormatException('Invalid HTTP response');
        status = int.parse(match.group(1)!);
        if (status >= 100 && status < 200) {
          throw const FormatException('Unexpected interim HTTP response');
        }
        for (final line in lines.skip(1)) {
          final separator = line.indexOf(':');
          if (separator > 0) {
            headers[line.substring(0, separator).toLowerCase()] = line
                .substring(separator + 1)
                .trim();
          }
        }
        // Redirect/error/full-file responses are header-only. The caller will
        // follow safe redirects or explain unsupported Range without the body.
        if (request.method == 'HEAD' || status != 206) break;
        body.add(buffer.sublist(headerEnd + 4));
        buffer = [];
      } else {
        body.add(chunk);
      }
      if (body.length > limit) {
        throw const FormatException('Server exceeded requested APK byte range');
      }
      if (body.length == limit) break;
    }
    if (status == null) {
      throw HttpException(
        'Windows HTTPS probe failed: $stderr',
        uri: request.url,
      );
    }
    if (status == 206 && request.method != 'HEAD' && body.length != limit) {
      throw const FormatException('Incomplete APK byte range');
    }
    return http.StreamedResponse(
      Stream.value(body.takeBytes()),
      status,
      headers: headers,
      request: request,
    );
  } finally {
    process.kill();
    await iterator.cancel();
    await errors.cancel();
    await process.exitCode;
  }
}

int _headerEnd(List<int> bytes) {
  for (var i = 0; i + 3 < bytes.length; i++) {
    if (bytes[i] == 13 &&
        bytes[i + 1] == 10 &&
        bytes[i + 2] == 13 &&
        bytes[i + 3] == 10) {
      return i;
    }
  }
  return -1;
}
