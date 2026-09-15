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

  group('sortDeviceFiles', () {
    List<DeviceFileEntry> sample() => [
      const DeviceFileEntry(
        name: 'beta.txt',
        path: '/sdcard/beta.txt',
        isDirectory: false,
        sizeBytes: 300,
        modified: '2024-03-01 10:00',
      ),
      const DeviceFileEntry(
        name: 'Alpha.txt',
        path: '/sdcard/Alpha.txt',
        isDirectory: false,
        sizeBytes: 1000,
        modified: '2024-01-01 10:00',
      ),
      const DeviceFileEntry(
        name: 'gamma.txt',
        path: '/sdcard/gamma.txt',
        isDirectory: false,
        sizeBytes: 20,
        modified: '2024-02-01 10:00',
      ),
      const DeviceFileEntry(
        name: 'Zips',
        path: '/sdcard/Zips',
        isDirectory: true,
        modified: '2024-05-01 10:00',
      ),
      const DeviceFileEntry(
        name: 'Docs',
        path: '/sdcard/Docs',
        isDirectory: true,
        modified: '2023-01-01 10:00',
      ),
    ];

    test('name order keeps directories first in both directions', () {
      final asc = sample();
      sortDeviceFiles(asc);
      expect(asc.map((e) => e.name), [
        'Docs',
        'Zips',
        'Alpha.txt',
        'beta.txt',
        'gamma.txt',
      ]);

      final desc = sample();
      sortDeviceFiles(desc, ascending: false);
      expect(desc.map((e) => e.name), [
        'Zips',
        'Docs',
        'gamma.txt',
        'beta.txt',
        'Alpha.txt',
      ]);
    });

    test('modified order uses the timestamp', () {
      final asc = sample();
      sortDeviceFiles(asc, sort: DeviceFileSort.modified);
      expect(asc.map((e) => e.name), [
        'Docs',
        'Zips',
        'Alpha.txt',
        'gamma.txt',
        'beta.txt',
      ]);

      final desc = sample();
      sortDeviceFiles(desc, sort: DeviceFileSort.modified, ascending: false);
      expect(desc.map((e) => e.name), [
        'Zips',
        'Docs',
        'beta.txt',
        'gamma.txt',
        'Alpha.txt',
      ]);
    });

    test(
      'size descending puts the largest file first, folders still on top',
      () {
        final entries = sample();
        sortDeviceFiles(entries, sort: DeviceFileSort.size, ascending: false);
        expect(entries.map((e) => e.name), [
          'Docs',
          'Zips',
          'Alpha.txt',
          'beta.txt',
          'gamma.txt',
        ]);
        expect(entries.take(2).every((e) => e.isDirectory), isTrue);
      },
    );

    test('missing size and timestamp fall back to name order', () {
      final entries = [
        const DeviceFileEntry(
          name: 'b.txt',
          path: '/sdcard/b.txt',
          isDirectory: false,
        ),
        const DeviceFileEntry(
          name: 'a.txt',
          path: '/sdcard/a.txt',
          isDirectory: false,
        ),
      ];

      sortDeviceFiles(entries, sort: DeviceFileSort.size);
      expect(entries.map((e) => e.name), ['a.txt', 'b.txt']);

      sortDeviceFiles(entries, sort: DeviceFileSort.modified);
      expect(entries.map((e) => e.name), ['a.txt', 'b.txt']);
    });

    test('unknown timestamps sort last when ascending', () {
      final entries = [
        const DeviceFileEntry(
          name: 'unknown.txt',
          path: '/sdcard/unknown.txt',
          isDirectory: false,
        ),
        const DeviceFileEntry(
          name: 'dated.txt',
          path: '/sdcard/dated.txt',
          isDirectory: false,
          modified: '2024-01-01 10:00',
        ),
      ];

      sortDeviceFiles(entries, sort: DeviceFileSort.modified);
      expect(entries.map((e) => e.name), ['dated.txt', 'unknown.txt']);
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
