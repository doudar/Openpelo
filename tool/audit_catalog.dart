// Run from the repository root: dart run tool/audit_catalog.dart [config.json]
// Read-only network audit; never starts ADB or installs an APK.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:openpelo/models/app_model.dart';
import 'package:openpelo/services/apk_probe_service.dart';
import 'package:openpelo/services/release_asset_selector.dart';

Future<void> main(List<String> args) async {
  final config =
      jsonDecode(
            await File(
              args.isEmpty ? 'apps_config.json' : args.single,
            ).readAsString(),
          )
          as Map<String, dynamic>;
  final releases = <String, Future<Map<String, dynamic>>>{};
  final probe = ApkProbeService();
  try {
    for (final entry in (config['apps'] as Map<String, dynamic>).entries) {
      final app = AppModel.fromJson(entry.key, entry.value);
      final record = <String, dynamic>{'app': app.name, 'source': app.url};
      try {
        var uri = Uri.parse(app.url);
        if (uri.host == 'github.com' &&
            uri.pathSegments.length >= 2 &&
            uri.pathSegments.contains('releases') &&
            uri.pathSegments.contains('latest')) {
          uri = Uri.https(
            'api.github.com',
            '/repos/${uri.pathSegments.take(2).join('/')}/releases/latest',
          );
        }
        if (uri.host == 'api.github.com') {
          final release = await releases.putIfAbsent(
            uri.toString(),
            () => readRelease(uri),
          );
          final assets = release['assets'] as List;
          final name = selectApkAssetName(
            assets.map((asset) => asset['name'] as String),
            exactName: app.assetName,
            globPattern: app.assetPattern,
          );
          uri = Uri.parse(
            assets.singleWhere(
                  (asset) => asset['name'] == name,
                )['browser_download_url']
                as String,
          );
        }
        // Keep the stable URL, not the expiring signed CDN redirect.
        record['download'] = uri.toString();
        final result = await probe.probe(uri);
        record['metadata'] = result.metadata.toJson();
        record['bytes'] = result.contentLength;
        record['status'] = 'verified';
      } catch (error) {
        record['status'] = 'unverified';
        record['error'] = error.toString();
        exitCode = 1;
      }
      stdout.writeln(jsonEncode(record));
    }
  } finally {
    probe.close();
  }
}

Future<Map<String, dynamic>> readRelease(Uri uri) async {
  String body;
  if (Platform.isWindows) {
    // Use the Windows certificate store, as the app's TLS fallback does.
    final result = await Process.run('curl.exe', [
      '--fail',
      '--silent',
      '--show-error',
      '--location',
      '--proto',
      '=https',
      '--proto-redir',
      '=https',
      '--max-time',
      '30',
      '--max-filesize',
      '8388608',
      '-H',
      'User-Agent: OpenPelo/1.0',
      '-H',
      'Accept: application/vnd.github+json',
      uri.toString(),
    ]);
    if (result.exitCode != 0) {
      throw HttpException('Release lookup failed: ${result.stderr}', uri: uri);
    }
    body = result.stdout as String;
  } else {
    final response = await http
        .get(
          uri,
          headers: {
            'User-Agent': 'OpenPelo/1.0',
            'Accept': 'application/vnd.github+json',
          },
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw HttpException(
        'Release lookup HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    body = response.body;
  }
  return jsonDecode(body) as Map<String, dynamic>;
}
