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

  entries.sort((a, b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return entries;
}
