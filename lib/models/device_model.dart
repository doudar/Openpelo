import 'dart:convert';

class DeviceModel {
  final String serial;
  final String status;
  final String transport; // 'usb' or 'wifi'
  final String? ip;
  final String? port;
  final String? name; // manufacturer + model
  final String? abi; // arm64-v8a or armeabi-v7a
  /// The complete ABI list reported by Android. Universal APKs are therefore
  /// represented without having to choose a single catalog architecture.
  final List<String> supportedAbis;
  final int? apiLevel;
  final String? androidVersion;
  final String? cpuDescription;
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
    List<String> supportedAbis = const [],
    this.apiLevel,
    this.androidVersion,
    this.cpuDescription,
    this.hardwareSerial,
    this.manufacturer,
  }) : supportedAbis = List.unmodifiable(supportedAbis);

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
            _stringListEquals(supportedAbis, other.supportedAbis) &&
            apiLevel == other.apiLevel &&
            androidVersion == other.androidVersion &&
            cpuDescription == other.cpuDescription &&
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
    Object.hashAll(supportedAbis),
    apiLevel,
    androidVersion,
    cpuDescription,
    hardwareSerial,
    manufacturer,
  );
}

bool _stringListEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
