import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/models/apk_metadata.dart';
import 'package:openpelo/models/app_model.dart';
import 'package:openpelo/models/device_model.dart';
import 'package:openpelo/providers/app_provider.dart';
import 'package:openpelo/services/catalog_service.dart';
import 'package:openpelo/services/config_service.dart';

class BatchProvider extends AppProvider {
  List<AppModel> installedBatch = [];
  @override
  Future<void> installCatalogApps(
    List<AppModel> apps,
    Future<bool> Function(String) onConfirmReinstall,
  ) async {
    installedBatch = apps;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled catalog has categories and the requested six recommended families',
    () async {
      final apps = await ConfigService().loadApps();
      final provider = BatchProvider();
      addTearDown(provider.dispose);
      provider.availableApps = apps;
      expect(apps.values.every((app) => app.category != 'Other'), isTrue);
      expect(provider.recommendedApps.map((app) => app.name), [
        'SmartSpin2k',
        'Grupetto',
        'MaterialFiles',
        'Lawnchair Launcher',
        'Aurora Store',
        'Moonlight Streaming',
      ]);
      provider.setAppSelected('FDroid', true);
      provider.setAppSelected('Grupetto', true);
      provider.setAppCategory('App stores');
      expect(
        provider.visibleApps.every((app) => app.category == 'App stores'),
        isTrue,
      );
      expect(provider.selectedAppCount, 2);
      await provider.installRecommendedApps((_) async => false);
      expect(
        provider.installedBatch.map((app) => app.name),
        provider.recommendedApps.map((app) => app.name),
      );
      expect(
        provider.installedBatch.any((app) => app.name == 'FDroid'),
        isFalse,
      );
      expect(provider.selectedAppCount, 2);
      await provider.installSelectedApps((_) async => false);
      expect(
        provider.installedBatch.map((app) => app.name),
        containsAll(['FDroid', 'Grupetto']),
      );
      expect(provider.installedBatch, hasLength(2));
    },
  );

  test(
    'device filtering selects compatible Lawnchair and drops unavailable apps',
    () async {
      final apps = await ConfigService().loadApps();
      final catalog = CatalogSnapshot(
        {
          for (final name in ['Lawnchair Launcher', 'Lawnchair Launcher Gen 1'])
            name: apps[name]!.withProbe(
              ApkMetadata(
                minSdk: name.endsWith('Gen 1') ? 21 : 26,
                nativeAbis: [],
              ),
              apps[name]!.url,
            ),
        },
        const {'Grupetto': 'Unavailable'},
      );
      final provider = BatchProvider();
      addTearDown(provider.dispose);
      DeviceModel device(int api) => DeviceModel(
        serial: 'demo',
        status: 'device',
        transport: 'usb',
        apiLevel: api,
        supportedAbis: ['arm64-v8a'],
      );
      provider.availableApps = catalog.forDevice(device(24));
      expect(provider.recommendedApps.single.name, 'Lawnchair Launcher Gen 1');
      await provider.installRecommendedApps((_) async => false);
      expect(provider.installedBatch.single.name, 'Lawnchair Launcher Gen 1');
      provider.setAppCategory('Launchers');
      provider.availableApps = catalog.forDevice(device(30));
      expect(provider.recommendedApps.single.name, 'Lawnchair Launcher');
      provider.availableApps = {};
      expect(provider.selectedAppCategory, 'Recommended');
      expect(provider.recommendedApps, isEmpty);
    },
  );
}
