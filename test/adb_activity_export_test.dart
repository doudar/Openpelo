import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/providers/app_provider.dart';

class ExportTestProvider extends AppProvider {
  Future<Uri?> Function(String fileName, Uint8List bytes)? onSave;
  String? capturedName;
  Uint8List? capturedBytes;

  @override
  Future<Uri?> saveAdbActivityFile(String fileName, Uint8List bytes) {
    capturedName = fileName;
    capturedBytes = bytes;
    return onSave!(fileName, bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'exports a stable UTF-8 snapshot without blocking other activity',
    () async {
      final provider = ExportTestProvider();
      addTearDown(provider.dispose);
      provider.logs = [
        LogEntry('[12:34:56]', 'adb devices', 'command'),
        LogEntry('[12:34:57]', 'Café ✓', 'info'),
      ];
      final picker = Completer<Uri?>();
      provider.onSave = (_, _) => picker.future;

      final export = provider.exportAdbActivity();
      expect(provider.isExportingAdbActivity, isTrue);
      expect(provider.isBusy, isFalse);
      expect(
        provider.capturedName,
        matches(RegExp(r'^openpelo_adb_activity_\d{8}_\d{6}\.txt$')),
      );
      expect(
        utf8.decode(provider.capturedBytes!),
        '[12:34:56] [command] adb devices\n'
        '[12:34:57] [info] Café ✓\n',
      );

      provider.logs.add(LogEntry('[12:34:58]', 'arrived later', 'info'));
      expect(await provider.exportAdbActivity(), isNull);
      picker.complete(Uri.file('/tmp/activity.txt'));
      expect(await export, Uri.file('/tmp/activity.txt').toFilePath());
      expect(provider.isExportingAdbActivity, isFalse);
      expect(provider.logs.last.message, contains('exported to'));
      expect(
        utf8.decode(provider.capturedBytes!),
        isNot(contains('arrived later')),
      );
    },
  );

  test(
    'empty activity skips the picker and cancellation remains silent',
    () async {
      final provider = ExportTestProvider();
      addTearDown(provider.dispose);
      provider.onSave = (_, _) async => null;

      expect(await provider.exportAdbActivity(), isNull);
      expect(provider.capturedBytes, isNull);

      provider.logs = [LogEntry('[00:00:00]', 'ready', 'status')];
      expect(await provider.exportAdbActivity(), isNull);
      expect(provider.isExportingAdbActivity, isFalse);
      expect(provider.logs.length, 1);
    },
  );

  test('save failures are reported and export state is reset', () async {
    final provider = ExportTestProvider();
    addTearDown(provider.dispose);
    provider.logs = [LogEntry('[00:00:00]', 'ready', 'status')];
    provider.onSave = (_, _) async => throw StateError('disk full');

    expect(await provider.exportAdbActivity(), isNull);
    expect(provider.isExportingAdbActivity, isFalse);
    expect(provider.logs.last.tag, 'error');
    expect(provider.logs.last.message, contains('disk full'));
  });
}
