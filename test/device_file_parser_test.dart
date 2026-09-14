import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/models/device_file_model.dart';
import 'package:openpelo/services/device_file_parser.dart';
import 'package:path/path.dart' as p;

void main() {
  group('parseLsOutput', () {
    test('parses toybox output with sizes and sorts directories first', () {
      const output = '''
total 24
drwxrwx--x  4 root sdcard_rw 4096 2024-01-01 12:00 .
drwxrwx--x 10 root sdcard_rw 4096 2024-01-01 12:00 ..
-rw-rw----  1 root sdcard_rw 2048 2024-03-05 09:30 zebra.txt
drwxrwx--x  2 root sdcard_rw 4096 2024-02-02 08:00 Download
-rw-rw----  1 root sdcard_rw  512 2024-03-06 10:15 My File.mp4
''';

      final entries = parseLsOutput(output, '/sdcard');

      expect(entries.map((e) => e.name), [
        'Download',
        'My File.mp4',
        'zebra.txt',
      ]);
      expect(entries[0].isDirectory, isTrue);
      expect(entries[0].path, '/sdcard/Download');
      expect(entries[0].sizeBytes, isNull);
      expect(entries[1].sizeBytes, 512);
      expect(entries[1].modified, '2024-03-06 10:15');
      expect(entries[2].sizeBytes, 2048);
    });

    test('parses legacy toolbox output without link counts or dir sizes', () {
      const output = '''
drwxrwx--x root     sdcard_rw          2016-05-01 12:00 DCIM
-rw-rw---- root     sdcard_rw     1024 2016-05-02 13:45 notes.txt
''';

      final entries = parseLsOutput(output, '/sdcard');

      expect(entries.length, 2);
      expect(entries[0].name, 'DCIM');
      expect(entries[0].isDirectory, isTrue);
      expect(entries[1].name, 'notes.txt');
      expect(entries[1].sizeBytes, 1024);
    });

    test('strips symlink targets and flags them', () {
      const output =
          'lrwxrwxrwx 1 root root 21 2024-01-01 00:00 sdcard -> /storage/self/primary';

      final entries = parseLsOutput(output, '/');

      expect(entries.single.name, 'sdcard');
      expect(entries.single.isSymlink, isTrue);
      expect(entries.single.isDirectory, isFalse);
      expect(entries.single.path, '/sdcard');
    });

    test('ignores unparseable lines', () {
      const output = 'ls: /data: Permission denied';
      expect(parseLsOutput(output, '/data'), isEmpty);
    });
  });

  group('path helpers', () {
    test('quoteShellArg escapes embedded single quotes', () {
      expect(quoteShellArg("Rock 'n' Roll"), r"'Rock '\''n'\'' Roll'");
      expect(quoteShellArg('/sdcard/My Folder'), "'/sdcard/My Folder'");
    });

    test('parentRemotePath walks up to root', () {
      expect(parentRemotePath('/sdcard/Download'), '/sdcard');
      expect(parentRemotePath('/sdcard'), '/');
      expect(parentRemotePath('/'), '/');
    });

    test('joinRemotePath normalizes separators', () {
      expect(joinRemotePath('/sdcard/', 'Movies'), '/sdcard/Movies');
      expect(joinRemotePath('/', 'sdcard'), '/sdcard');
    });

    test('safeLocalEntryPath rejects host path traversal', () {
      expect(
        () => safeLocalEntryPath('downloads', r'..\outside.txt'),
        throwsFormatException,
      );
      expect(
        () => safeLocalEntryPath('downloads', '../outside.txt'),
        throwsFormatException,
      );
      expect(
        p.basename(safeLocalEntryPath('downloads', 'inside.txt')),
        'inside.txt',
      );
    });
  });

  group('formatFileSize', () {
    test('formats byte counts', () {
      expect(formatFileSize(512), '512 B');
      expect(formatFileSize(2048), '2.0 KB');
      expect(formatFileSize(5 * 1024 * 1024), '5.0 MB');
      expect(formatFileSize(150 * 1024 * 1024), '150 MB');
    });
  });
}
