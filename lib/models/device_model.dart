class DeviceModel {
  final String serial;
  final String status;
  final String transport; // 'usb' or 'wifi'
  final String? ip;
  final String? port;
  final String? name; // manufacturer + model
  final String? abi; // arm64-v8a or armeabi-v7a

  DeviceModel({
    required this.serial,
    required this.status, 
    required this.transport,
    this.ip,
    this.port,
    this.name,
    this.abi,
  });

  String get displayName {
    if (transport == 'wifi' && ip != null) {
      return "$name • WiFi ($ip${port!=null ?':$port':''})";
    }
    return "$name • USB";
  }
}
