// Render the production widgets with sample data; never initialize ADB.
// Run manually: flutter test tool/capture_readme_screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/screens/home_screen.dart';
import 'package:openpelo/theme/app_theme.dart';
import 'package:openpelo/models/device_file_model.dart';
import 'package:openpelo/models/device_model.dart';
import 'package:openpelo/models/device_resources.dart';
import 'package:openpelo/models/apk_metadata.dart';
import 'package:openpelo/models/installed_app_model.dart';
import 'package:openpelo/providers/app_provider.dart';
import 'package:openpelo/services/config_service.dart';
import 'package:provider/provider.dart';

class _ScreenshotProvider extends AppProvider {
  _ScreenshotProvider() {
    final device = DeviceModel(
      serial: 'documentation-device',
      status: 'device',
      transport: 'wifi',
      ip: '192.0.2.10',
      port: '5555',
      name: 'Peloton PLTN-RB1VO-2',
      abi: 'arm64-v8a',
      supportedAbis: ['arm64-v8a', 'armeabi-v7a'],
      apiLevel: 24,
      androidVersion: '7.0',
    );
    devices = [device];
    selectedDevice = device;
    selectedDeviceResources = const DeviceResources(
      ramTotalBytes: 4 * 1024 * 1024 * 1024,
      ramAvailableBytes: 1536 * 1024 * 1024,
      cpuMaxKhz: 2200000,
      storageTotalBytes: 24 * 1024 * 1024 * 1024,
      storageUsedBytes: 8 * 1024 * 1024 * 1024,
      storageAvailableBytes: 16 * 1024 * 1024 * 1024,
    );
    statusMessage = 'Connected to ${device.displayName}';
    currentAppVersion = RegExp(
      r'^version: (.+)$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!.trim();
    logs = [
      LogEntry('[10:30:00]', 'Device connected via WiFi.', 'status'),
      LogEntry('[10:30:01]', 'Device architecture: arm64-v8a', 'info'),
      LogEntry('[10:30:01]', 'Compatible application catalog loaded.', 'info'),
    ];
  }

  @override
  String get saveLocation => r'C:\OpenPelo\Downloads';

  @override
  Future<List<InstalledAppModel>> listInstalledApps({
    bool includeSystemApps = false,
  }) async => const [
    InstalledAppModel(
      packageName: 'com.aurora.store',
      label: 'Aurora Store',
      isSystemApp: false,
    ),
    InstalledAppModel(
      packageName: 'org.mozilla.focus',
      label: 'Firefox Focus',
      isSystemApp: false,
    ),
    InstalledAppModel(
      packageName: 'app.lawnchair',
      label: 'Lawnchair',
      isSystemApp: false,
    ),
    InstalledAppModel(
      packageName: 'me.zhanghai.android.files',
      label: 'Material Files',
      isSystemApp: false,
    ),
  ];

  @override
  Future<List<DeviceFileEntry>> listDeviceFiles(
    String deviceSerial,
    String path,
  ) async => [
    for (final name in ['DCIM', 'Download', 'Movies', 'Music', 'Pictures'])
      DeviceFileEntry(
        name: name,
        path: '$path/$name',
        isDirectory: true,
        modified: '2026-09-15 10:30:00',
      ),
    DeviceFileEntry(
      name: 'workout-notes.txt',
      path: '$path/workout-notes.txt',
      isDirectory: false,
      sizeBytes: 2048,
      modified: '2026-09-15 10:30:00',
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture README screens with sample device data', (tester) async {
    // Flutter tests otherwise use the unreadable Ahem test font. Override this
    // path with OPENPELO_SCREENSHOT_FONT on non-Windows hosts.
    final fontPath =
        Platform.environment['OPENPELO_SCREENSHOT_FONT'] ??
        r'C:\Windows\Fonts\segoeui.ttf';
    final font = ByteData.sublistView(File(fontPath).readAsBytesSync());
    final emojiFile = File(r'C:\Windows\Fonts\seguiemj.ttf');
    if (emojiFile.existsSync()) {
      await (FontLoader('ScreenshotEmoji')..addFont(
            Future.value(ByteData.sublistView(emojiFile.readAsBytesSync())),
          ))
          .load();
    }
    for (final family in [
      'Ahem',
      'Roboto',
      'Segoe UI',
      'Consolas',
      'monospace',
    ]) {
      final loader = FontLoader(family)..addFont(Future.value(font));
      if (emojiFile.existsSync()) {
        loader.addFont(
          Future.value(ByteData.sublistView(emojiFile.readAsBytesSync())),
        );
      }
      await loader.load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);

    // Default desktop window, allowing for the native title bar.
    tester.view.physicalSize = const Size(1100, 770);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = _ScreenshotProvider();
    final sources = await ConfigService().loadApps();
    // Metadata confirmed from the official APKs, kept deterministic for rendering.
    provider.availableApps = {
      for (final name in ['Grupetto', 'Lawnchair Launcher Gen 1'])
        name: sources[name]!.withProbe(
          ApkMetadata(minSdk: 21, nativeAbis: []),
          sources[name]!.url,
        ),
    };
    provider.availableApps['Grupetto']!.isSelected = true;
    provider.catalogStatus =
        '2 compatible applications shown for this sample device';
    final boundaryKey = GlobalKey();
    final theme = AppTheme.light;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            // A fontless app-bar style otherwise falls back to the test font.
            theme: theme.copyWith(
              textTheme: theme.textTheme.apply(
                fontFamilyFallback: const ['ScreenshotEmoji'],
              ),
              appBarTheme: theme.appBarTheme.copyWith(
                titleTextStyle: theme.appBarTheme.titleTextStyle!.copyWith(
                  fontFamily: 'Segoe UI',
                ),
              ),
            ),
            home: const HomeScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('images/screenshots/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('overview');
    await tester.tap(find.text('Wi-Fi ADB'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I'm Ready - Connect Device"));
    await tester.pumpAndSettle();
    await capture('wireless-connection');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    Future<void> openTool(String label) async {
      await tester.tap(find.byTooltip('Open tools menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await openTool('Installed App Manager');
    await capture('installed-app-manager');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await openTool('File Manager');
    await capture('file-manager');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open tools menu'));
    await tester.pumpAndSettle();
    await capture('tools');

    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
    debugDisableShadows = true;
  });
}
