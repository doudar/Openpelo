import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/models/device_model.dart';

void main() {
  test('device equality includes connection details', () {
    final usb = DeviceModel(
      serial: 'abc',
      status: 'device',
      transport: 'usb',
      name: 'Peloton Bike',
      abi: 'arm64-v8a',
    );
    final sameUsb = DeviceModel(
      serial: 'abc',
      status: 'device',
      transport: 'usb',
      name: 'Peloton Bike',
      abi: 'arm64-v8a',
    );
    final wifi = DeviceModel(
      serial: 'abc',
      status: 'device',
      transport: 'wifi',
      ip: '192.168.1.20',
      port: '5555',
      name: 'Peloton Bike',
      abi: 'arm64-v8a',
    );

    expect(usb, sameUsb);
    expect(usb.hashCode, sameUsb.hashCode);
    expect(usb, isNot(wifi));
  });

  test('device equality includes capability metadata and list contents', () {
    final first = DeviceModel(
      serial: 'abc',
      status: 'device',
      transport: 'usb',
      supportedAbis: ['arm64-v8a', 'armeabi-v7a'],
      apiLevel: 24,
      androidVersion: '7.0',
      cpuDescription: 'ruby',
    );
    final same = DeviceModel(
      serial: 'abc',
      status: 'device',
      transport: 'usb',
      supportedAbis: ['arm64-v8a', 'armeabi-v7a'],
      apiLevel: 24,
      androidVersion: '7.0',
      cpuDescription: 'ruby',
    );
    final changedAbi = DeviceModel(
      serial: 'abc',
      status: 'device',
      transport: 'usb',
      supportedAbis: ['armeabi-v7a'],
      apiLevel: 24,
      androidVersion: '7.0',
      cpuDescription: 'ruby',
    );

    expect(first, same);
    expect(first.hashCode, same.hashCode);
    expect(first, isNot(changedAbi));
    expect(first.supportedAbis, isA<List<String>>());
  });
}
