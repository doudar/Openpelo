import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/models/app_model.dart';

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
}
