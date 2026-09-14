import 'package:path/path.dart' as p;
import '../models/device_file_model.dart';

final _posix = p.posix;

/// Quotes [value] for safe use inside an Android shell command string.
String quoteShellArg(String value) => "'${value.replaceAll("'", r"'\''")}'";

String joinRemotePath(String dir, String name) =>
    _posix.normalize(_posix.join(dir, name));

String parentRemotePath(String path) {
  final normalized = _posix.normalize(path);
  if (normalized == '/' || normalized.isEmpty) return '/';
  return _posix.dirname(normalized);
}

/// Builds a local destination for a remote entry without allowing the remote
/// name to introduce host path separators or escape [root].
String safeLocalEntryPath(String root, String name) {
  if (name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.contains('/') ||
      name.contains(r'\')) {
    throw FormatException('Unsupported device filename: $name');
  }

  final normalizedRoot = p.normalize(p.absolute(root));
  final candidate = p.normalize(p.join(normalizedRoot, name));
  if (!p.isWithin(normalizedRoot, candidate)) {
    throw FormatException('Device filename escapes the save location: $name');
  }
  return candidate;
}

final _lsLine = RegExp(
  r'^([\-dlcbps])[rwxsStT\-]{9}[+.@]?\s+(.*?)\s*(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}(?::\d{2})?)\s(.*)$',
);

/// Parses `ls -la` output from Android's toybox or legacy toolbox shells.
///
/// Toybox:  `drwxrwx--x 2 root sdcard_rw 4096 2024-01-01 12:00 Name`
/// Toolbox: `drwxrwx--x root sdcard_rw 2024-01-01 12:00 Name`
List<DeviceFileEntry> parseLsOutput(String output, String parentPath) {
  final entries = <DeviceFileEntry>[];

  for (final rawLine in output.split('\n')) {
    final line = rawLine.trimRight();
    if (line.isEmpty || line.startsWith('total ')) continue;

    final match = _lsLine.firstMatch(line);
    if (match == null) continue;

    final typeChar = match.group(1)!;
    final middle = match.group(2)!.trim();
    final date = match.group(3)!;
    final time = match.group(4)!;
    var name = match.group(5)!;

    final isSymlink = typeChar == 'l';
    if (isSymlink) {
      final arrow = name.indexOf(' -> ');
      if (arrow >= 0) name = name.substring(0, arrow);
    }
    if (name.isEmpty || name == '.' || name == '..') continue;

    int? size;
    final middleTokens = middle.split(RegExp(r'\s+'));
    if (middleTokens.length >= 3) {
      size = int.tryParse(middleTokens.last);
    }

    entries.add(
      DeviceFileEntry(
        name: name,
        path: joinRemotePath(parentPath, name),
        isDirectory: typeChar == 'd',
        isSymlink: isSymlink,
        sizeBytes: typeChar == '-' ? size : null,
        modified: '$date $time',
      ),
    );
  }

  sortDeviceFiles(entries);
  return entries;
}

/// Column a device listing can be ordered by.
enum DeviceFileSort { name, modified, size }

/// Sorts [entries] in place. Directories always stay grouped above files; the
/// [sort] column and [ascending] direction apply within each group. Entries
/// missing a size or timestamp fall back to case-insensitive name order.
void sortDeviceFiles(
  List<DeviceFileEntry> entries, {
  DeviceFileSort sort = DeviceFileSort.name,
  bool ascending = true,
}) {
  int byName(DeviceFileEntry a, DeviceFileEntry b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  entries.sort((a, b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;

    var result = 0;
    switch (sort) {
      case DeviceFileSort.name:
        result = byName(a, b);
      case DeviceFileSort.modified:
        // Timestamps are 'YYYY-MM-DD HH:MM[:SS]', so string order is time
        // order. Unknown timestamps sort last when ascending.
        final am = a.modified;
        final bm = b.modified;
        if (am == null || bm == null) {
          result = am == bm ? 0 : (am == null ? 1 : -1);
        } else {
          result = am.compareTo(bm);
        }
      case DeviceFileSort.size:
        result = (a.sizeBytes ?? -1).compareTo(b.sizeBytes ?? -1);
    }

    if (result == 0) return byName(a, b);
    return ascending ? result : -result;
  });
}
