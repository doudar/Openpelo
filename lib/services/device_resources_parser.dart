import 'dart:convert';

import '../models/device_resources.dart';

const deviceResourcesMeminfoMarker = '__OPENPELO_MEMINFO__';
const deviceResourcesCpuMarker = '__OPENPELO_CPU_MAX_KHZ__';
const deviceResourcesDfKilobytesMarker = '__OPENPELO_DF_K_DATA__';
const deviceResourcesDfFallbackMarker = '__OPENPELO_DF_DATA__';

/// One read-only shell probe. Read both df formats because old Android toolbox
/// builds may not support -k, and their default output uses human units.
const deviceResourcesProbeCommand =
    r'printf "__OPENPELO_MEMINFO__\n"; cat /proc/meminfo 2>/dev/null; '
    r'printf "__OPENPELO_CPU_MAX_KHZ__\n"; '
    r'for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/cpuinfo_max_freq '
    r'/sys/devices/system/cpu/cpufreq/policy*/cpuinfo_max_freq; do '
    r'if [ -r "$f" ]; then cat "$f" 2>/dev/null; fi; done; '
    r'printf "__OPENPELO_DF_K_DATA__\n"; df -k /data 2>/dev/null; '
    r'printf "__OPENPELO_DF_DATA__\n"; df /data 2>/dev/null';

const _maxCapacityBytes = 1 << 50; // Reject implausible or corrupt readings.

DeviceResources parseDeviceResources(String output) {
  final sections = <String, List<String>>{};
  String? currentSection;
  for (final line in const LineSplitter().convert(output)) {
    final marker = line.trim();
    if (marker == deviceResourcesMeminfoMarker ||
        marker == deviceResourcesCpuMarker ||
        marker == deviceResourcesDfKilobytesMarker ||
        marker == deviceResourcesDfFallbackMarker) {
      currentSection = marker;
      sections[currentSection] = <String>[];
    } else if (currentSection != null) {
      sections[currentSection]!.add(line);
    }
  }

  final memory = _parseMemory(
    sections[deviceResourcesMeminfoMarker] ?? const [],
  );
  final cpuMaxKhz = _parseCpuMax(
    sections[deviceResourcesCpuMarker] ?? const [],
  );
  final storage =
      _parseStorage(sections[deviceResourcesDfKilobytesMarker] ?? const []) ??
      _parseStorage(sections[deviceResourcesDfFallbackMarker] ?? const []);
  return DeviceResources(
    ramTotalBytes: memory.$1,
    ramAvailableBytes: memory.$2,
    cpuMaxKhz: cpuMaxKhz,
    storageTotalBytes: storage?.$1,
    storageUsedBytes: storage?.$2,
    storageAvailableBytes: storage?.$3,
  );
}

(int?, int?) _parseMemory(List<String> lines) {
  int? total;
  int? available;
  final pattern = RegExp(r'^(MemTotal|MemAvailable):\s*(\d+)\s+kB\s*$');
  for (final line in lines) {
    final match = pattern.firstMatch(line.trim());
    if (match == null) continue;
    final kilobytes = int.tryParse(match.group(2)!);
    if (kilobytes == null || kilobytes < 0) continue;
    final bytes = kilobytes * 1024;
    if (bytes > _maxCapacityBytes) continue;
    if (match.group(1) == 'MemTotal' && bytes > 0) total = bytes;
    if (match.group(1) == 'MemAvailable') available = bytes;
  }
  if (total != null && available != null && available > total) {
    available = null;
  }
  return (total, available);
}

int? _parseCpuMax(List<String> lines) {
  int? highest;
  for (final line in lines) {
    final value = line.trim();
    if (!RegExp(r'^\d+$').hasMatch(value)) continue;
    final khz = int.tryParse(value);
    // These sysfs files report kHz. Avoid showing corrupt or unit-mismatched
    // values as a CPU clock.
    if (khz == null || khz < 10000 || khz > 10000000) continue;
    if (highest == null || khz > highest) highest = khz;
  }
  return highest;
}

(int, int, int)? _parseStorage(List<String> lines) {
  final headerIndex = lines.indexWhere(
    (line) => RegExp(r'^\s*Filesystem\b', caseSensitive: false).hasMatch(line),
  );
  if (headerIndex < 0) return null;
  final header = lines[headerIndex];
  final blockSize = _blockSizeFromHeader(header);
  if (blockSize == null && !RegExp(r'\bSize\b').hasMatch(header)) {
    return null;
  }

  (int, int, int)? firstValid;
  for (final line in lines.skip(headerIndex + 1)) {
    final columns = line.trim().split(RegExp(r'\s+'));
    if (columns.length < 3) continue;
    final values = _parseStorageColumns(columns, blockSize);
    if (values == null) continue;
    firstValid ??= values;
    // A wrapped filesystem name can put the mount point on its second line.
    if (columns.last == '/data') return values;
  }
  // The command queried /data directly. Older toolbox df lacks a mount column.
  return firstValid;
}

int? _blockSizeFromHeader(String header) {
  if (RegExp(
    r'\b(?:1K|1024)-blocks\b',
    caseSensitive: false,
  ).hasMatch(header)) {
    return 1024;
  }
  if (RegExp(r'\b512-blocks\b', caseSensitive: false).hasMatch(header)) {
    return 512;
  }
  return null;
}

(int, int, int)? _parseStorageColumns(List<String> columns, int? blockSize) {
  for (var i = 0; i + 2 < columns.length; i++) {
    final total = _parseQuantity(columns[i], blockSize);
    final used = _parseQuantity(columns[i + 1], blockSize);
    final available = _parseQuantity(columns[i + 2], blockSize);
    if (total == null || used == null || available == null) continue;
    if (total <= 0 ||
        total > _maxCapacityBytes ||
        used > total ||
        available > total) {
      continue;
    }
    // Human-readable df values are rounded independently. Allow up to 2%
    // rounding slack while rejecting clearly inconsistent filesystems.
    if (used + available > total + total ~/ 50) continue;
    return (total, used, available);
  }
  return null;
}

int? _parseQuantity(String token, int? blockSize) {
  final match = RegExp(
    r'^(\d+)(?:\.(\d+))?([KMGTPE]?)(?:i?B)?$',
    caseSensitive: false,
  ).firstMatch(token);
  if (match == null) return null;
  final whole = match.group(1)!;
  final fraction = match.group(2) ?? '';
  final suffix = match.group(3)!.toUpperCase();
  if (whole.length + fraction.length > 16) return null;
  if (suffix.isEmpty &&
      blockSize == null &&
      !token.toUpperCase().endsWith('B')) {
    // Bare numbers under toolbox's Size header have no reliable unit.
    return null;
  }
  var unit = suffix.isEmpty
      ? (token.toUpperCase().endsWith('B') ? 1 : blockSize!)
      : 1;
  const suffixes = 'KMGTPE';
  if (suffix.isNotEmpty) {
    for (var i = 0; i <= suffixes.indexOf(suffix); i++) {
      unit *= 1024;
    }
  }
  var denominator = 1;
  for (var i = 0; i < fraction.length; i++) {
    denominator *= 10;
  }
  final scaled = int.tryParse('$whole$fraction');
  if (scaled == null) return null;
  final bytes = scaled * unit ~/ denominator;
  return bytes <= _maxCapacityBytes ? bytes : null;
}
