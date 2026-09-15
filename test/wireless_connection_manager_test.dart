import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/models/device_model.dart';
import 'package:openpelo/services/adb_service.dart';
import 'package:openpelo/services/wireless_connection_manager.dart';

const ip = '192.168.1.172';
const endpoint = '$ip:5555';
const hardwareId = 'PELOTON123';
const identityKey = '["Peloton Interactive LLC","PELOTON123"]';
const tlsSerial = 'adb-PELOTON123-test (2)._adb-tls-connect._tcp';

DeviceModel peloton({bool legacy = false, String address = ip}) => DeviceModel(
  serial: legacy ? '$address:5555' : tlsSerial,
  status: 'device',
  transport: 'wifi',
  ip: legacy ? address : null,
  port: legacy ? '5555' : null,
  name: 'Peloton Interactive LLC PLTN-RB1VO-2',
  hardwareSerial: hardwareId,
  manufacturer: 'Peloton Interactive LLC',
);

final kindle = DeviceModel(
  serial: 'KINDLE123',
  status: 'device',
  transport: 'usb',
  name: 'Amazon KFRAPWI',
  manufacturer: 'Amazon',
  hardwareSerial: 'KINDLE123',
);

class FakeAdb extends AdbService {
  final List<String> calls = [];
  String expectedIdentity = identityKey;
  bool listenerEnabled = false;
  bool reachable = true;
  bool wrongEndpoint = false;
  bool wrongSource = false;
  bool identityTimeout = false;
  String address = ip;
  Completer<void>? connectionGate;

  FakeAdb() : super(onLog: (_, _) {});

  @override
  bool get isMobile => false;

  @override
  Future<bool> isExpectedDevice(String serial, String id) async {
    calls.add('verify $serial $id');
    if (serial.endsWith(':5555') && identityTimeout) {
      throw TimeoutException('identity');
    }
    return id == expectedIdentity &&
        !(serial.endsWith(':5555') ? wrongEndpoint : wrongSource);
  }

  @override
  Future<String?> getDeviceIp(String serial) async {
    calls.add('ip $serial');
    return address;
  }

  @override
  Future<void> connectLegacyWifi(String address) async {
    calls.add('connect $address:5555');
    if (connectionGate != null) await connectionGate!.future;
    if (!listenerEnabled || !reachable) throw StateError('Connection refused');
  }

  @override
  Future<void> connectTcpIp(String serial) async {
    calls.add('tcpip $serial');
    listenerEnabled = true;
  }

  @override
  Future<void> disconnectEndpoint(String serial) async {
    calls.add('disconnect $serial');
  }
}

void main() {
  late FakeAdb adb;
  late WirelessConnectionManager manager;
  late List<String> saved;
  late List<bool> busy;
  late DateTime clock;

  setUp(() {
    adb = FakeAdb();
    saved = [];
    busy = [];
    clock = DateTime(2026, 9, 15);
    manager = WirelessConnectionManager(
      adb: adb,
      save: (data) async {
        saved.add(data);
      },
      onBusy: busy.add,
      now: () => clock,
      delay: (_) async {},
    );
  });

  test(
    'sets up verified Peloton, resolves IP before restart, leaves Kindle alone',
    () async {
      expect(await manager.maintain([kindle, peloton()]), isTrue);
      expect(adb.calls, [
        'verify $tlsSerial $identityKey',
        'ip $tlsSerial',
        'connect $endpoint',
        'verify $tlsSerial $identityKey',
        'tcpip $tlsSerial',
        'connect $endpoint',
        'verify $endpoint $identityKey',
      ]);
      expect(jsonDecode(saved.single), {identityKey: ip});
      expect(busy, [true, false]);
    },
  );

  test('reconnects after app restart with no TLS transport', () async {
    manager.restore(jsonEncode({identityKey: ip}));
    adb.listenerEnabled = true;
    expect(await manager.maintain([kindle]), isTrue);
    expect(adb.calls, ['connect $endpoint', 'verify $endpoint $identityKey']);
    expect(saved, isEmpty);
  });

  test(
    'learns an already connected legacy endpoint without restarting ADB',
    () async {
      expect(await manager.maintain([peloton(legacy: true), kindle]), isTrue);
      adb.calls.clear();
      expect(
        await manager.maintain([peloton(), peloton(legacy: true), kindle]),
        isFalse,
      );
      expect(adb.calls, isEmpty);
    },
  );

  test(
    'does not configure USB-only or unidentified wireless devices',
    () async {
      expect(
        await manager.maintain([
          kindle,
          DeviceModel(
            serial: 'other:5555',
            status: 'device',
            transport: 'wifi',
            name: 'Amazon Kindle',
          ),
          DeviceModel(
            serial: tlsSerial,
            status: 'device',
            transport: 'wifi',
            name: 'Peloton tablet',
          ),
        ]),
        isFalse,
      );
      expect(adb.calls, isEmpty);
    },
  );

  test(
    'automatically sets up and remembers a non-Peloton wireless device',
    () async {
      final tablet = DeviceModel(
        serial: 'adb-TABLET123._adb-tls-connect._tcp',
        status: 'device',
        transport: 'wifi',
        name: 'Samsung tablet',
        manufacturer: 'Samsung',
        hardwareSerial: 'TABLET123',
      );
      adb.expectedIdentity = tablet.identityKey!;
      expect(await manager.maintain([kindle, tablet]), isTrue);
      expect(adb.calls, contains('tcpip ${tablet.serial}'));
      expect(jsonDecode(saved.single), {tablet.identityKey: ip});
      final restored = WirelessConnectionManager(
        adb: adb,
        save: (_) async {},
        onBusy: (_) {},
      )..restore(saved.single);
      adb.calls.clear();
      expect(await restored.maintain([kindle]), isTrue);
      expect(adb.calls, [
        'connect $endpoint',
        'verify $endpoint ${tablet.identityKey}',
      ]);
    },
  );

  test(
    'rejects source identity mismatch before saving or enabling TCP/IP',
    () async {
      adb.wrongSource = true;
      expect(await manager.maintain([peloton()]), isFalse);
      expect(adb.calls, ['verify $tlsSerial $identityKey']);
      expect(saved, isEmpty);
    },
  );

  test(
    'disconnects a reassigned IP and never configures its new occupant',
    () async {
      manager.restore(jsonEncode({identityKey: ip}));
      adb.listenerEnabled = true;
      adb.wrongEndpoint = true;
      expect(await manager.maintain([]), isFalse);
      expect(adb.calls, [
        'connect $endpoint',
        'verify $endpoint $identityKey',
        'disconnect $endpoint',
      ]);
    },
  );

  test(
    'disconnects a newly connected endpoint if identity verification times out',
    () async {
      manager.restore(jsonEncode({identityKey: ip}));
      adb.listenerEnabled = true;
      adb.identityTimeout = true;
      expect(await manager.maintain([]), isFalse);
      expect(adb.calls.last, 'disconnect $endpoint');
    },
  );

  test(
    'leaves an existing unrelated connection at the old IP untouched',
    () async {
      manager.restore(jsonEncode({identityKey: ip}));
      expect(
        await manager.maintain([
          DeviceModel(
            serial: endpoint,
            status: 'device',
            transport: 'wifi',
            name: 'Amazon Kindle',
          ),
        ]),
        isFalse,
      );
      expect(adb.calls, isEmpty);
    },
  );

  test('updates remembered IP from a verified TLS connection', () async {
    manager.restore(jsonEncode({identityKey: '192.168.1.10'}));
    adb.listenerEnabled = true;
    expect(await manager.maintain([peloton()]), isTrue);
    expect(jsonDecode(saved.single), {identityKey: ip});
    expect(adb.calls, isNot(contains('connect 192.168.1.10:5555')));
  });

  test('backs off failures and resets after recovery', () async {
    manager.restore(jsonEncode({identityKey: ip}));
    expect(await manager.maintain([]), isFalse);
    clock = clock.add(const Duration(seconds: 5));
    await manager.maintain([]);
    expect(adb.calls.length, 1);
    clock = clock.add(const Duration(seconds: 5));
    await manager.maintain([]);
    expect(adb.calls.length, 2);
    clock = clock.add(const Duration(seconds: 19));
    await manager.maintain([]);
    expect(adb.calls.length, 2);
    clock = clock.add(const Duration(seconds: 1));
    adb.listenerEnabled = true;
    expect(await manager.maintain([]), isTrue);
    expect(await manager.maintain([]), isTrue);
  });

  test('does not overlap attempts or restart ADB after disposal', () async {
    adb.connectionGate = Completer<void>();
    final pending = manager.maintain([peloton()]);
    // Allow identity, IP lookup and preference saving to complete.
    await Future<void>.delayed(Duration.zero);
    expect(await manager.maintain([peloton()]), isFalse);
    manager.dispose();
    adb.connectionGate!.complete();
    expect(await pending, isFalse);
    expect(adb.calls.where((c) => c.startsWith('tcpip')), isEmpty);
    expect(busy, [true, false]);
  });

  test('ignores damaged preferences and stops after disposal', () async {
    manager.restore('{broken');
    manager.restore(jsonEncode({'bad': 'not-an-ip', '': ip}));
    expect(await manager.maintain([]), isFalse);
    manager.dispose();
    expect(await manager.maintain([peloton()]), isFalse);
    expect(adb.calls, isEmpty);
  });

  test(
    'prefers legacy Peloton while preserving Kindle and USB connections',
    () {
      final usb = DeviceModel(
        serial: hardwareId,
        status: 'device',
        transport: 'usb',
        name: 'Peloton tablet',
        hardwareSerial: hardwareId,
        manufacturer: 'Peloton Interactive LLC',
      );
      final legacy = peloton(legacy: true);
      expect(prioritizeDeviceConnections([kindle, peloton(), legacy, usb]), [
        legacy,
        usb,
        kindle,
      ]);
    },
  );

  test('sorts Pelotons first and deduplicates other manufacturers too', () {
    final otherTls = DeviceModel(
      serial: 'adb-other._adb-tls-connect._tcp',
      status: 'device',
      transport: 'wifi',
      manufacturer: 'Samsung',
      hardwareSerial: 'other',
    );
    final otherLegacy = DeviceModel(
      serial: '192.168.1.20:5555',
      status: 'device',
      transport: 'wifi',
      port: '5555',
      manufacturer: 'Samsung',
      hardwareSerial: 'other',
    );
    final bike = peloton();
    expect(prioritizeDeviceConnections([kindle, otherTls, bike, otherLegacy]), [
      bike,
      kindle,
      otherLegacy,
    ]);
  });
}
