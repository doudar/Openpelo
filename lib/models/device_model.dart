import 'dart:convert';

class DeviceModel {
  final String serial;
  final String status;
  final String transport; // 'usb' or 'wifi'
  final String? ip;
  final String? port;
  final String? name; // manufacturer + model
  final String? abi; // arm64-v8a or armeabi-v7a
  final String? hardwareSerial;
  final String? manufacturer;

  DeviceModel({
    required this.serial,
    required this.status,
    required this.transport,
    this.ip,
    this.port,
    this.name,
    this.abi,
    this.hardwareSerial,
    this.manufacturer,
  });

  String? get identityKey => manufacturer == null || hardwareSerial == null
      ? null
      : jsonEncode([manufacturer, hardwareSerial]);

  bool get isPeloton => RegExp(
    r'^peloton(?:\s|$)',
    caseSensitive: false,
  ).hasMatch(manufacturer ?? name ?? '');

  String get displayName {
    if (transport == 'wifi' && ip != null) {
      return "$name • WiFi ($ip${port != null ? ':$port' : ''})";
    }
    if (transport == 'wifi') return "$name • WiFi";
    return "$name • USB";
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DeviceModel &&
            serial == other.serial &&
            status == other.status &&
            transport == other.transport &&
            ip == other.ip &&
            port == other.port &&
            name == other.name &&
            abi == other.abi &&
            hardwareSerial == other.hardwareSerial &&
            manufacturer == other.manufacturer;
  }

  @override
  int get hashCode => Object.hash(
    serial,
    status,
    transport,
    ip,
    port,
    name,
    abi,
    hardwareSerial,
    manufacturer,
  );
}
