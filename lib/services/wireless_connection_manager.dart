import 'dart:convert';
import 'dart:io';

import '../models/device_model.dart';
import 'adb_service.dart';

/// Remembers verified devices, never arbitrary addresses found on the network.
class WirelessConnectionManager {
  final AdbService adb;
  final Future<void> Function(String) save;
  final void Function(bool) onBusy;
  final DateTime Function() now;
  final Future<void> Function(Duration) delay;
  final Map<String, String> _addresses = {};
  final Map<String, DateTime> _retryAt = {};
  final Map<String, int> _failures = {};
  bool _running = false;
  bool _disposed = false;

  WirelessConnectionManager({
    required this.adb,
    required this.save,
    required this.onBusy,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  }) : now = now ?? DateTime.now,
       delay = delay ?? Future<void>.delayed;

  void restore(String? data) {
    if (data == null) return;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) return;
      for (final entry in decoded.entries) {
        if (_validIdentity(entry.key) &&
            entry.value is String &&
            _validIp(entry.value as String)) {
          _addresses[entry.key] = entry.value as String;
        }
      }
    } on FormatException {
      // A damaged preference must not prevent normal USB or Wi-Fi connections.
    }
  }

  static bool _validIdentity(String value) {
    try {
      final parts = jsonDecode(value);
      return parts is List &&
          parts.length == 2 &&
          parts.every((part) => part is String && part.trim().isNotEmpty) &&
          parts[1].toString().toLowerCase() != 'unknown';
    } on FormatException {
      return false;
    }
  }

  static bool _validIp(String value) {
    final address = InternetAddress.tryParse(value);
    return address != null &&
        address.type == InternetAddressType.IPv4 &&
        !address.isLoopback &&
        value != '0.0.0.0' &&
        value != '255.255.255.255';
  }

  bool get _active => !_disposed;

  /// Runs at most one setup/reconnect per heartbeat. The caller skips this
  /// during installs, recordings and other device operations.
  Future<bool> maintain(List<DeviceModel> devices) async {
    if (!_active || _running || adb.isMobile) return false;
    _running = true;
    try {
      final candidates = <String, DeviceModel>{};
      for (final device in devices) {
        final id = device.identityKey;
        if (id == null || !_validIdentity(id) || device.transport != 'wifi') {
          continue;
        }
        // Prefer the legacy endpoint if both TLS and legacy are advertised.
        if (!candidates.containsKey(id) || device.port == '5555') {
          candidates[id] = device;
        }
      }
      final ids = {...candidates.keys, ..._addresses.keys};
      for (final id in ids) {
        if (!_active) break;
        final device = candidates[id];
        if (device?.port == '5555' && _addresses[id] == device?.ip) {
          _failures.remove(id);
          _retryAt.remove(id);
          continue;
        }
        final retry = _retryAt[id];
        if (retry != null && now().isBefore(retry)) continue;
        onBusy(true);
        try {
          return await _maintainDevice(id, device, devices);
        } catch (error) {
          final failures = (_failures[id] ?? 0) + 1;
          _failures[id] = failures;
          // 10, 20, 40, 80, 160, then 300 seconds; no overlapping retries.
          final seconds = failures >= 6 ? 300 : 5 * (1 << failures);
          _retryAt[id] = now().add(Duration(seconds: seconds));
          if (_active && failures == 1) {
            adb.onLog(
              'WiFi connection unavailable; retrying automatically. '
                  'After a reboot, enable Wireless debugging once to set it up again. '
                  '($error)',
              'info',
            );
          }
        } finally {
          onBusy(false);
        }
        return false;
      }
      return false;
    } finally {
      _running = false;
    }
  }

  Future<bool> _maintainDevice(
    String id,
    DeviceModel? device,
    List<DeviceModel> devices,
  ) async {
    String? ip = _addresses[id];
    if (device != null) {
      if (!await adb.isExpectedDevice(device.serial, id)) {
        throw StateError('Device identity could not be verified');
      }
      if (!_active) return false;
      // Resolve before tcpip restarts adbd and closes the original transport.
      ip = device.ip ?? await adb.getDeviceIp(device.serial);
    }
    if (ip == null || !_validIp(ip)) {
      throw StateError('No usable device WiFi address');
    }
    if (!_active) return false;
    final endpoint = '$ip:5555';
    // Do not interfere with another device already using a remembered IP.
    if (devices.any((d) => d.serial == endpoint && d.identityKey != id)) {
      throw StateError('The saved address belongs to another device');
    }
    if (_addresses[id] != ip && device != null) {
      _addresses[id] = ip;
      await save(jsonEncode(_addresses));
    }
    if (!_active) return false;

    if (device?.serial != endpoint) {
      try {
        await adb.connectLegacyWifi(ip);
      } catch (_) {
        // Without an existing authenticated connection we cannot re-enable
        // the listener. Retry the saved endpoint later, without scanning.
        if (device == null || !_active) rethrow;
        if (!await adb.isExpectedDevice(device.serial, id)) {
          throw StateError('Device identity changed before setup');
        }
        if (!_active) return false;
        adb.onLog('Enabling automatic WiFi connection at $endpoint.', 'info');
        await adb.connectTcpIp(device.serial);
        await delay(const Duration(seconds: 2));
        if (!_active) return false;
        await adb.connectLegacyWifi(ip);
      }
    }
    // A DHCP address may now belong to a different authorized Android device.
    try {
      if (!await adb.isExpectedDevice(endpoint, id)) {
        throw StateError(
          'The saved address did not identify the expected device',
        );
      }
    } catch (_) {
      if (!devices.any((d) => d.serial == endpoint)) {
        await adb.disconnectEndpoint(endpoint);
      }
      rethrow;
    }
    if (!_active) return false;
    _failures.remove(id);
    _retryAt.remove(id);
    adb.onLog(
      'Connected at $endpoint. Automatic reconnection is ready.',
      'info',
    );
    return true;
  }

  void dispose() {
    _disposed = true;
  }
}

/// Prefer port 5555 for each device, then put Pelotons first without filtering
/// out other manufacturers. Preserve relative order within each group.
List<DeviceModel> prioritizeDeviceConnections(List<DeviceModel> devices) {
  final legacyIds = devices
      .where(
        (d) =>
            d.transport == 'wifi' && d.port == '5555' && d.identityKey != null,
      )
      .map((d) => d.identityKey)
      .toSet();
  final unique = devices
      .where(
        (d) =>
            d.transport != 'wifi' ||
            d.port == '5555' ||
            !legacyIds.contains(d.identityKey),
      )
      .toList();
  return [
    ...unique.where((d) => d.isPeloton),
    ...unique.where((d) => !d.isPeloton),
  ];
}
