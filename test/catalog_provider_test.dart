import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/models/app_model.dart';
import 'package:openpelo/models/apk_metadata.dart';
import 'package:openpelo/models/device_model.dart';
import 'package:openpelo/models/device_resources.dart';
import 'package:openpelo/services/adb_service.dart';
import 'package:openpelo/providers/app_provider.dart';
import 'package:openpelo/services/catalog_service.dart';
import 'package:openpelo/services/config_service.dart';

class TestConfig extends ConfigService {
  @override
  Future<Map<String, AppModel>> loadApps() async => {};
}

class NoResourceAdb extends AdbService {
  NoResourceAdb() : super(onLog: (_, _) {});
  @override
  Future<DeviceResources> getDeviceResources(String serial) async =>
      const DeviceResources();
}

class PendingCatalog extends CatalogService {
  final pending = <Completer<CatalogSnapshot>>[];
  @override
  Future<CatalogSnapshot> refresh(
    Iterable<AppModel> sources, {
    required Future<String> Function(AppModel) resolveUrl,
    bool force = false,
  }) {
    final completer = Completer<CatalogSnapshot>();
    pending.add(completer);
    return completer.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'device switch immediately clears and ignores stale catalog results',
    () async {
      final catalog = PendingCatalog();
      final provider = AppProvider(
        configService: TestConfig(),
        adbService: NoResourceAdb(),
        catalogService: catalog,
      );
      addTearDown(provider.dispose);
      DeviceModel device(String serial, int api) => DeviceModel(
        serial: serial,
        status: 'device',
        transport: 'usb',
        apiLevel: api,
        supportedAbis: ['arm64-v8a'],
      );
      final old = device('old', 24);
      final modern = device('modern', 30);
      final app =
          AppModel(
            name: 'Modern',
            description: '',
            url: 'https://example.org/a.apk',
          ).withProbe(
            ApkMetadata(minSdk: 26, nativeAbis: []),
            'https://example.org/a.apk',
          );
      provider.availableApps = {'Modern': app};
      provider.selectDevice(old);
      expect(provider.availableApps, isEmpty);
      await Future<void>.delayed(Duration.zero);
      provider.selectDevice(modern);
      await Future<void>.delayed(Duration.zero);
      catalog.pending[1].complete(CatalogSnapshot({'Modern': app}, {}));
      await Future<void>.delayed(Duration.zero);
      expect(provider.availableApps.keys, ['Modern']);
      catalog.pending[0].complete(const CatalogSnapshot({}, {}));
      await Future<void>.delayed(Duration.zero);
      expect(provider.availableApps.keys, ['Modern']);
      expect(provider.isCheckingCatalog, isFalse);
    },
  );

  test(
    'unknown device API is reported without a catalog network probe',
    () async {
      final catalog = PendingCatalog();
      final provider = AppProvider(
        configService: TestConfig(),
        adbService: NoResourceAdb(),
        catalogService: catalog,
      );
      addTearDown(provider.dispose);
      provider.selectDevice(
        DeviceModel(serial: 'unknown', status: 'device', transport: 'usb'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(catalog.pending, isEmpty);
      expect(provider.catalogStatus, contains('API level unavailable'));
      expect(provider.availableApps, isEmpty);
    },
  );

  test(
    'same-device refresh preserves checked APKs but source changes clear them',
    () async {
      final catalog = PendingCatalog();
      final provider = AppProvider(
        configService: TestConfig(),
        adbService: NoResourceAdb(),
        catalogService: catalog,
      );
      addTearDown(provider.dispose);
      final device = DeviceModel(
        serial: 'old',
        status: 'device',
        transport: 'usb',
        apiLevel: 24,
        supportedAbis: ['arm64-v8a'],
      );
      AppModel app(String url) => AppModel(
        name: 'App',
        description: '',
        url: url,
      ).withProbe(ApkMetadata(minSdk: 21, nativeAbis: []), url);
      provider.selectDevice(device);
      await Future<void>.delayed(Duration.zero);
      catalog.pending[0].complete(
        CatalogSnapshot({'App': app('https://example.org/v1.apk')}, {}),
      );
      await Future<void>.delayed(Duration.zero);
      provider.setAppSelected('App', true);
      final refresh = provider.refreshCatalog();
      await Future<void>.delayed(Duration.zero);
      catalog.pending[1].complete(
        CatalogSnapshot({'App': app('https://example.org/v1.apk')}, {}),
      );
      await refresh;
      expect(provider.availableApps['App']!.isSelected, isTrue);
      final changed = provider.refreshCatalog();
      await Future<void>.delayed(Duration.zero);
      catalog.pending[2].complete(
        CatalogSnapshot({'App': app('https://example.org/v2.apk')}, {}),
      );
      await changed;
      expect(provider.availableApps['App']!.isSelected, isFalse);
    },
  );
}
