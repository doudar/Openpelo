class DeviceFileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final bool isSymlink;
  final int? sizeBytes;
  final String? modified;

  const DeviceFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.isSymlink = false,
    this.sizeBytes,
    this.modified,
  });
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value >= 100
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}
