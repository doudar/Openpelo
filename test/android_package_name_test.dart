import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/services/android_package_name.dart';

void main() {
  test('accepts dotted identifiers', () {
    const names = [
      'com.example.app',
      'org.cagnulen.qdomyoszwift',
      'a.b',
      'com.example.app_2.Sub_1',
      'com.onepeloton.systempluginui',
    ];
    for (final name in names) {
      expect(isValidAndroidPackageName(name), isTrue, reason: name);
    }
  });

  test(
    'rejects anything the device shell could read as more than one word',
    () {
      const names = [
        '',
        'app',
        'com.example.app; rm -rf /sdcard',
        'com.example.app && id',
        'com.example.app\$(id)',
        'com.example.app`id`',
        'com.example.app app2',
        "com.example.app'",
        'com..example',
        '.com.example',
        'com.example.',
        'com.1example.app',
        'com.example.app\n',
        'com.example-app',
      ];
      for (final name in names) {
        expect(isValidAndroidPackageName(name), isFalse, reason: name);
      }
    },
  );
}
