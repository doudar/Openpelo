import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/services/release_asset_selector.dart';

void main() {
  group('selectApkAssetName', () {
    test('prefers an exact configured asset', () {
      final selected = selectApkAssetName([
        'notes.txt',
        'app-arm64.apk',
        'app-universal.apk',
      ], exactName: 'app-universal.apk');

      expect(selected, 'app-universal.apk');
    });

    test('supports a case-insensitive glob pattern', () {
      final selected = selectApkAssetName([
        'SkyTubeLegacy-Legacy-Extra-2.999.apk',
        'other.apk',
      ], globPattern: 'skytubelegacy-legacy-extra-*.apk');

      expect(selected, 'SkyTubeLegacy-Legacy-Extra-2.999.apk');
    });

    test('uses the only APK when no configured name matches', () {
      final selected = selectApkAssetName([
        'release-notes.txt',
        'NewPipe_v0.29.1.apk',
      ], exactName: 'NewPipe_v0.28.8.apk');

      expect(selected, 'NewPipe_v0.29.1.apk');
    });

    test('rejects ambiguous releases', () {
      expect(
        () => selectApkAssetName(['arm.apk', 'x86.apk']),
        throwsStateError,
      );
    });
  });
}
