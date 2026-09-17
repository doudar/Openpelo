import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/models/app_model.dart';
import 'package:openpelo/models/apk_metadata.dart';

void main() {
  test('keeps release asset metadata separate from Android package ID', () {
    final app = AppModel.fromJson('Example', {
      'url': 'https://example.com/app.apk',
      'asset_name': 'example-arm64.apk',
      'asset_pattern': 'example-*.apk',
      'package_id': 'com.example.app',
      'sha256': 'abc123',
      'abi': 'arm64-v8a',
    });

    expect(app.assetName, 'example-arm64.apk');
    expect(app.assetPattern, 'example-*.apk');
    expect(app.packageId, 'com.example.app');
    expect(app.sha256, 'abc123');
  });

  test('defaults optional catalog classification fields', () {
    final app = AppModel.fromJson('Example', {'url': 'https://example.com'});

    expect(app.category, 'Other');
    expect(app.recommendationId, isNull);
    expect(app.recommendationPriority, 0);
  });

  test('probe result preserves catalog classification fields', () {
    final app = AppModel.fromJson('Example', {
      'url': 'https://example.com',
      'category': 'Launchers',
      'recommendation_id': 'lawnchair',
      'recommendation_priority': 1,
    });
    final probed = app.withProbe(
      ApkMetadata(minSdk: 26, nativeAbis: []),
      'https://example.com/app.apk',
    );

    expect(probed.category, 'Launchers');
    expect(probed.recommendationId, 'lawnchair');
    expect(probed.recommendationPriority, 1);
  });
}
