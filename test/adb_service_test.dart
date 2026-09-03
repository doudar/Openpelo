import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/services/adb_service.dart';

void main() {
  group('parsePlatformToolsRevision', () {
    test('reads the package revision', () {
      const properties = '''
Pkg.Desc = Android SDK Platform-Tools
Pkg.Revision = 37.0.1
''';

      expect(parsePlatformToolsRevision(properties), '37.0.1');
    });

    test('returns null when the revision is absent', () {
      expect(
        parsePlatformToolsRevision('Pkg.Desc = Android SDK Platform-Tools'),
        isNull,
      );
    });
  });
}
