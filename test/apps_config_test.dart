import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/models/app_model.dart';
import 'package:openpelo/services/release_asset_selector.dart';

void main() {
  final catalog =
      (jsonDecode(File('apps_config.json').readAsStringSync())
              as Map<String, dynamic>)['apps']
          as Map<String, dynamic>;

  test('bundled catalog has usable HTTPS APK source definitions', () {
    for (final entry in catalog.entries) {
      final app = AppModel.fromJson(entry.key, entry.value);
      final uri = Uri.parse(app.url);
      expect(uri.scheme, 'https', reason: app.name);
      expect(uri.host, isNotEmpty, reason: app.name);
      expect(app.description, isNotEmpty, reason: app.name);
      expect(app.category, isNot('Other'), reason: app.name);
      expect(app.assetName, endsWith('.apk'), reason: app.name);
      if (app.sha256 != null) {
        expect(app.sha256, matches(r'^[a-f0-9]{64}$'), reason: app.name);
      }
    }
  });

  test(
    'Jellyfin selects only the mobile Libre release APK after an update',
    () {
      final app = AppModel.fromJson('Jellyfin', catalog['Jellyfin']);
      expect(
        selectApkAssetName(
          [
            'jellyfin-android-v2.8.0-libre-debug.apk',
            'jellyfin-android-v2.8.0-libre-release.aab',
            'jellyfin-android-v2.8.0-libre-release.apk',
            'jellyfin-android-v2.8.0-proprietary-debug.apk',
            'jellyfin-android-v2.8.0-proprietary-release.apk',
            'jellyfin-androidtv-v0.20.0-release.apk',
          ],
          exactName: app.assetName,
          globPattern: app.assetPattern,
        ),
        'jellyfin-android-v2.8.0-libre-release.apk',
      );
    },
  );
}
