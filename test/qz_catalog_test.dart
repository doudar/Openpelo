import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/services/config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'catalog exposes every QZ nightly APK variant through latest URLs',
    () async {
      final apps = await ConfigService().loadApps();
      final qz = {
        for (final entry in apps.entries)
          if (entry.key.startsWith('QZ ')) entry.key: entry.value,
      };

      expect(
        qz.keys,
        containsAll(<String>[
          'QZ Standard Nightly',
          'QZ NordicTrack Treadmill Nightly',
          'QZ NordicTrack Bike Nightly',
          'QZ NordicTrack Rower Nightly',
          'QZ FitPro Treadmill Nightly',
          'QZ FitPro Bike Nightly',
          'QZ FitPro Elliptical Nightly',
          'QZ FitPro Rower Nightly',
          'QZ Peloton Bike Nightly',
          'QZ Peloton Bike+ Nightly',
        ]),
      );
      expect(qz, hasLength(10));

      for (final app in qz.values) {
        expect(
          app.url,
          startsWith(
            'https://github.com/cagnulein/qdomyos-zwift/releases/latest/download/',
          ),
        );
        expect(app.assetName, endsWith('.apk'));
        expect(app.packageId, 'org.cagnulen.qdomyoszwift');
        expect(app.category, 'Fitness');
      }
    },
  );
}
