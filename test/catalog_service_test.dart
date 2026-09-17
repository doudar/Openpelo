import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openpelo/models/app_model.dart';
import 'package:openpelo/models/apk_metadata.dart';
import 'package:openpelo/models/device_model.dart';
import 'package:openpelo/services/apk_probe_service.dart';
import 'package:openpelo/services/catalog_service.dart';

class FakeProbe extends ApkProbeService {
  int calls = 0;
  bool unavailable = false;
  ApkProbeResult? previousResult;
  @override
  Future<ApkProbeResult> probe(Uri uri, {ApkProbeResult? previous}) async {
    calls++;
    previousResult = previous;
    if (unavailable) throw const ApkProbeException('HTTP 404');
    return ApkProbeResult(
      metadata: ApkMetadata(minSdk: 21, nativeAbis: []),
      contentLength: 100000,
      resolvedUrl: uri.toString(),
      etag: '"v1"',
    );
  }
}

DeviceModel target(int? api, List<String> abis) => DeviceModel(
  serial: 'test',
  status: 'device',
  transport: 'usb',
  apiLevel: api,
  supportedAbis: abis,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final source = AppModel(
    name: 'Example',
    description: '',
    url: 'https://example.com/app.apk',
  );

  test('filters actual ABI and API including universal and 32-bit support', () {
    AppModel app(String name, int minSdk, List<String> abis) => AppModel(
      name: name,
      description: '',
      url: source.url,
    ).withProbe(ApkMetadata(minSdk: minSdk, nativeAbis: abis), source.url);
    final snapshot = CatalogSnapshot({
      'universal': app('universal', 21, []),
      'modern': app('modern', 26, []),
      'arm32': app('arm32', 21, ['armeabi-v7a']),
      'x86': app('x86', 21, ['x86']),
    }, {});
    expect(snapshot.forDevice(target(24, ['arm64-v8a', 'armeabi-v7a'])).keys, [
      'universal',
      'arm32',
    ]);
    expect(snapshot.forDevice(target(26, ['arm64-v8a'])).keys, [
      'universal',
      'modern',
    ]);
    expect(snapshot.forDevice(target(24, [])).keys, ['universal']);
    expect(snapshot.forDevice(target(null, ['arm64-v8a'])), isEmpty);
  });

  test(
    'persists probes and avoids network checks until daily expiry',
    () async {
      var now = DateTime.utc(2026, 9, 17);
      final probe = FakeProbe();
      addTearDown(probe.close);
      var resolutions = 0;
      Future<String> resolve(AppModel app) async {
        resolutions++;
        return app.url;
      }

      final service = CatalogService(probeService: probe, now: () => now);
      final first = await service.refresh([source], resolveUrl: resolve);
      expect(first.verifiedApps.keys, ['Example']);
      expect(probe.calls, 1);
      final restored = CatalogService(probeService: probe, now: () => now);
      await restored.refresh([source], resolveUrl: resolve);
      expect(probe.calls, 1);
      expect(resolutions, 1);
      now = now.add(const Duration(hours: 25));
      await restored.refresh([source], resolveUrl: resolve);
      expect(probe.calls, 2);
      expect(probe.previousResult, isNotNull);
    },
  );

  test(
    'removes missing APKs and retries failures without a full download',
    () async {
      var now = DateTime.utc(2026, 9, 17);
      final probe = FakeProbe();
      addTearDown(probe.close);
      final service = CatalogService(probeService: probe, now: () => now);
      Future<String> resolve(AppModel app) async => app.url;
      await service.refresh([source], resolveUrl: resolve);
      probe.unavailable = true;
      final missing = await service.refresh(
        [source],
        resolveUrl: resolve,
        force: true,
      );
      expect(missing.verifiedApps, isEmpty);
      expect(missing.unavailable['Example'], contains('404'));
      await service.refresh([source], resolveUrl: resolve);
      expect(probe.calls, 2);
      now = now.add(const Duration(hours: 2));
      probe.unavailable = false;
      expect(
        (await service.refresh([source], resolveUrl: resolve)).verifiedApps,
        isNotEmpty,
      );
      expect(probe.calls, 3);
    },
  );

  test('changed source configuration invalidates cached metadata', () async {
    final probe = FakeProbe();
    addTearDown(probe.close);
    final service = CatalogService(probeService: probe);
    Future<String> resolve(AppModel app) async => app.url;
    await service.refresh([source], resolveUrl: resolve);
    final replacement = AppModel(
      name: source.name,
      description: '',
      url: 'https://example.com/replacement.apk',
    );
    await service.refresh([replacement], resolveUrl: resolve);
    expect(probe.calls, 2);
    expect(probe.previousResult, isNull);
  });
}
