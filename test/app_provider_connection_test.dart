import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/models/device_model.dart';
import 'package:openpelo/providers/app_provider.dart';
import 'package:openpelo/services/adb_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceListAdb extends AdbService {
  List<DeviceModel> devices = [];
  DeviceListAdb() : super(onLog: (_, _) {});
  @override
  Future<List<DeviceModel>> getConnectedDevices() async => devices;
  @override
  Future<bool> isExpectedDevice(String serial, String identityKey) async =>
      devices.any((d) => d.serial == serial && d.identityKey == identityKey);
}

DeviceModel device(String manufacturer, String id, String endpoint) =>
    DeviceModel(
      serial: endpoint,
      status: 'device',
      transport: 'wifi',
      ip: endpoint.split(':').first,
      port: endpoint.split(':').last,
      name: '$manufacturer tablet',
      manufacturer: manufacturer,
      hardwareSerial: id,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Peloton sorts first without replacing a manually selected other device',
    () async {
      SharedPreferences.setMockInitialValues({});
      final adb = DeviceListAdb();
      final provider = AppProvider(adbService: adb);
      addTearDown(provider.dispose);
      final kindle = device('Amazon', 'kindle', '192.168.1.10:5555');
      final bike = device(
        'Peloton Interactive LLC',
        'bike',
        '192.168.1.20:5555',
      );
      adb.devices = [kindle];
      await provider.refresh();
      provider.selectDevice(kindle);
      adb.devices = [kindle, bike];
      await provider.refresh();
      expect(provider.devices, [bike, kindle]);
      expect(provider.selectedDevice, kindle);
    },
  );

  test(
    'reassigned endpoint cannot silently change the selected device',
    () async {
      SharedPreferences.setMockInitialValues({});
      final adb = DeviceListAdb();
      final provider = AppProvider(adbService: adb);
      addTearDown(provider.dispose);
      final bike = device(
        'Peloton Interactive LLC',
        'bike',
        '192.168.1.20:5555',
      );
      adb.devices = [bike];
      await provider.refresh();
      expect(provider.selectedDevice, bike);
      final other = device('Amazon', 'kindle', bike.serial);
      adb.devices = [other];
      await provider.refresh();
      expect(provider.selectedDevice, isNull);
      expect(provider.devices, [other]);
      final recovered = device(
        'Peloton Interactive LLC',
        'bike',
        '192.168.1.30:5555',
      );
      adb.devices = [other, recovered];
      await provider.refresh();
      expect(provider.selectedDevice, recovered);
    },
  );
}
