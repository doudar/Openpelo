import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:openpelo/models/device_model.dart';
import 'package:openpelo/models/device_resources.dart';
import 'package:openpelo/models/app_model.dart';
import 'package:openpelo/providers/app_provider.dart';
import 'package:openpelo/screens/home_screen.dart';
import 'package:openpelo/theme/app_theme.dart';
import 'package:openpelo/widgets/log_panel.dart';
import 'package:openpelo/widgets/app_list_widget.dart';

void main() {
  for (final scenario in [
    (const Size(1280, 900), 1.0, false),
    (const Size(1100, 770), 1.0, false),
    (const Size(1000, 660), 1.0, true),
    (const Size(1000, 660), 1.5, true),
    (const Size(390, 844), 1.0, false),
  ]) {
    final (size, textScale, updateNotice) = scenario;
    testWidgets('device details and controls fit $scenario', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = AppProvider();
      addTearDown(provider.dispose);
      final device = DeviceModel(
        serial: 'demo',
        status: 'device',
        transport: 'usb',
        name: 'Peloton Ruby',
        apiLevel: 24,
        androidVersion: '7.0',
        abi: 'arm64-v8a',
        supportedAbis: ['arm64-v8a', 'armeabi-v7a'],
      );
      provider.devices = [device];
      provider.selectedDevice = device;
      if (size.width != 1280) {
        provider.availableApps = {
          'Grupetto': AppModel(
            name: 'Grupetto',
            description: 'Bike metrics overlay',
            url: 'https://example.org/grupetto.apk',
            category: 'Fitness',
            recommendationId: 'grupetto',
          ),
        };
      }
      provider.selectedDeviceResources = const DeviceResources(
        ramTotalBytes: 4 * 1024 * 1024 * 1024,
        ramAvailableBytes: 1536 * 1024 * 1024,
        cpuMaxKhz: 2200000,
        storageTotalBytes: 24 * 1024 * 1024 * 1024,
        storageUsedBytes: 8 * 1024 * 1024 * 1024,
        storageAvailableBytes: 16 * 1024 * 1024 * 1024,
      );
      provider.statusMessage = 'Connected to Peloton Ruby';
      provider.catalogStatus =
          '22 compatible · 1 incompatible · 2 unavailable or unverified. Checked daily.';
      provider.logs = [LogEntry('[12:00:00]', 'Device connected', 'status')];
      if (updateNotice) {
        provider.currentAppVersion = '1.0.76';
        provider.latestAppVersion = '1.0.77';
      }
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('7.0'), findsWidgets);
      expect(find.textContaining('24'), findsWidgets);
      expect(find.textContaining('arm64-v8a'), findsWidgets);
      expect(find.text('2.20 GHz'), findsOneWidget);
      expect(find.textContaining('4.0 GiB total'), findsWidgets);
      expect(find.textContaining('16.0 GiB available'), findsOneWidget);
      if (size.width >= 900 && textScale == 1) {
        final logBounds = tester.getRect(find.byType(LogPanel));
        expect(logBounds.bottom, lessThanOrEqualTo(size.height));
        expect(logBounds.height, greaterThan(80));
        expect(
          tester.getSize(find.byType(AppListWidget)).height,
          greaterThan(100),
        );
        expect(find.text('Export').hitTestable(), findsOneWidget);
      } else {
        // Narrow windows and large text retain scrolling access to the log.
        await tester.ensureVisible(find.text('Export'));
        await tester.pumpAndSettle();
        expect(find.text('Export').hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
