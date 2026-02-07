import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
// Mobile dependencies
import 'package:flutter_adb/flutter_adb.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/device_model.dart';

class AdbService {
  String? _adbPath;
  Function(String message, String tag) onLog;
  
  // Mobile Adb Client state
  String? _connectedIp;
  int _connectedPort = 5555;

  AdbService({required this.onLog});

  bool get isMobile => Platform.isAndroid || Platform.isIOS;

  Future<void> init() async {
    if (isMobile) {
      onLog("Mobile Mode: Using native Dart ADB client.", 'info');
      // No binary extraction needed for mobile
      return;
    }

    try {
      final dir = await getApplicationSupportDirectory();
      final adbDir = Directory(p.join(dir.path, 'platform-tools'));
      String adbExecutableName = Platform.isWindows ? 'adb.exe' : 'adb';
      _adbPath = p.join(adbDir.path, adbExecutableName);

      if (!await File(_adbPath!).exists()) {
        onLog("Setting up ADB...", 'info');
        // Need to extract
        String zipAsset = '';
        if (Platform.isWindows) {
          zipAsset = 'ADB/platform-tools-latest-windows.zip';
        } else if (Platform.isMacOS) {
          zipAsset = 'ADB/platform-tools-latest-darwin.zip';
        } else if (Platform.isLinux) {
          zipAsset = 'ADB/platform-tools-latest-linux.zip';
        }

        if (zipAsset.isNotEmpty) {
           final byteData = await rootBundle.load(zipAsset);
           final bytes = byteData.buffer.asUint8List();
           final archive = ZipDecoder().decodeBytes(bytes);
           
           for (final file in archive) {
            final filename = file.name;
            if (file.isFile) {
              final data = file.content as List<int>;
              final outFile = File(p.join(dir.path, filename));
              await outFile.parent.create(recursive: true);
              await outFile.writeAsBytes(data);
              
              if (!Platform.isWindows && filename.endsWith('adb')) {
                 // Make executable
                 await Process.run('chmod', ['+x', outFile.path]);
              }
            }
           }
           onLog("ADB extraction complete.", 'info');
        }
      }
      
      // Ensure executable permissions are set on Mac/Linux even if file already existed
      if (!Platform.isWindows && _adbPath != null) {
          await Process.run('/bin/chmod', ['+x', _adbPath!]);
      }
    } catch (e) {
      onLog("Error initializing ADB: $e", 'error');
    }
  }

  Future<ProcessResult> runAdbCommand(List<String> args) async {
    if (isMobile) {
       // Mobile stub for unsupported methods called via raw runAdb
       return ProcessResult(0, 1, "", "Command not supported on mobile via runAdbCommand encapsulation.");
    }

    if (_adbPath == null) await init();
    if (_adbPath == null) throw Exception("ADB not found");

    onLog("\$ adb ${args.join(' ')}", 'command');
    try {
      final result = await Process.run(_adbPath!, args);
      if (result.stdout.toString().isNotEmpty) {
         // Filter out empty lines
         final lines = result.stdout.toString().trim();
         if (lines.isNotEmpty) onLog(lines, 'stdout');
      }
      if (result.stderr.toString().isNotEmpty) {
         onLog(result.stderr.toString().trim(), 'stderr');
      }
      return result;
    } catch (e) {
      onLog("Command failed: $e", 'error');
      rethrow;
    }
  }

  Future<List<DeviceModel>> getConnectedDevices() async {
    if (isMobile) {
      if (_connectedIp != null) {
        // Ping to verify
        try {
          final out = await Adb.sendSingleCommand('getprop ro.product.model', ip: _connectedIp!, port: _connectedPort);
          if (out.isNotEmpty) {
             String? name = await getDeviceName(_connectedIp!);
             String? abi = await getDeviceAbi(_connectedIp!);
             return [
               DeviceModel(
                 serial: "$_connectedIp:$_connectedPort",
                 status: "device",
                 transport: 'wifi',
                 ip: _connectedIp,
                 port: _connectedPort.toString(),
                 name: name,
                 abi: abi
               )
             ];
          }
        } catch (e) {
          // Lost connection
          _connectedIp = null;
        }
      }
      return [];
    }

    try {
      final result = await runAdbCommand(['devices']);
      final output = result.stdout.toString();
      final lines = output.split('\n').where((l) => l.trim().isNotEmpty).toList();
      
      List<DeviceModel> devices = [];
      // Skip first line "List of devices attached"
      for (var i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 2) continue;
        
        final serial = parts[0];
        final status = parts[1];

        if (status != 'device') continue;

        String transport = 'usb';
        String? ip;
        String? port;

        if (serial.contains(':')) {
          transport = 'wifi';
          final hostParts = serial.split(':');
          ip = hostParts[0];
          port = hostParts.length > 1 ? hostParts[1] : null;
        }

        // Get Name
        String? name = await getDeviceName(serial);
        String? abi = await getDeviceAbi(serial);

        devices.add(DeviceModel(
          serial: serial,
          status: status,
          transport: transport,
          ip: ip,
          port: port,
          name: name,
          abi: abi,
        ));
      }
      return devices;
    } catch (e) {
      return [];
    }
  }

  Future<String?> getDeviceAbi(String serial) async {
    if (isMobile) {
      if (_connectedIp == null) return null;
      return await Adb.sendSingleCommand('getprop ro.product.cpu.abi', ip: _connectedIp!, port: _connectedPort);
    }
    try {
      final result = await runAdbCommand(['-s', serial, 'shell', 'getprop', 'ro.product.cpu.abi']);
      return result.stdout.toString().trim();
    } catch (e) {
      return null;
    }
  }

  Future<String?> getDeviceName(String serial) async {
    if (isMobile) {
       if (_connectedIp == null) return serial;
       final manufacturer = await Adb.sendSingleCommand('getprop ro.product.manufacturer', ip: _connectedIp!, port: _connectedPort);
       final model = await Adb.sendSingleCommand('getprop ro.product.model', ip: _connectedIp!, port: _connectedPort);
       return "$manufacturer $model".trim();
    }

    try {
      // manufacturer
       final manResult = await runAdbCommand(['-s', serial, 'shell', 'getprop', 'ro.product.manufacturer']);
       final manufacturer = manResult.stdout.toString().trim();
       
       // model
       final modelResult = await runAdbCommand(['-s', serial, 'shell', 'getprop', 'ro.product.model']);
       final model = modelResult.stdout.toString().trim();

       return "$manufacturer $model".trim();
    } catch (e) {
      return serial;
    }
  }

  Future<String> installApk(String serial, String apkPath) async {
    if (isMobile) {
      if (_connectedIp == null) return "Error: Not connected";
      try {
         onLog("Uploading and installing APK...", 'info');
         // Use the new installApk method from the fork
         bool success = await Adb.installApk(apkPath, ip: _connectedIp!, port: _connectedPort);
         if (success) {
           return "Success";
         } else {
           return "Error: Installation returned false";
         }
      } catch (e) {
         return "Error installing APK: $e";
      }
    }

    final result = await runAdbCommand(['-s', serial, 'install', '-r', '-d', '-g', '-t', apkPath]);
    return result.stdout.toString() + result.stderr.toString();
  }

  Future<String> uninstallPackage(String serial, String packageName) async {
    if (isMobile) {
       if (_connectedIp == null) return "Error: Not connected";
       final out = await Adb.sendSingleCommand('pm uninstall $packageName', ip: _connectedIp!, port: _connectedPort);
       return out.isEmpty ? "Success" : out; // adb shell pm uninstall returns 'Success' or 'Failure' usually
    }

    final result = await runAdbCommand(['-s', serial, 'uninstall', packageName]);
    return result.stdout.toString() + result.stderr.toString();
  }

  Future<String> uninstallPackageUser0(String serial, String packageName) async {
    if (isMobile) {
       if (_connectedIp == null) return "Error: Not connected";
       final out = await Adb.sendSingleCommand('pm uninstall --user 0 $packageName', ip: _connectedIp!, port: _connectedPort);
       return out;
    }

    final result = await runAdbCommand(['-s', serial, 'shell', 'pm', 'uninstall', '--user', '0', packageName]);
    return result.stdout.toString() + result.stderr.toString();
  }

  Future<List<String>> listPackages(String serial) async {
      if (isMobile) {
        if (_connectedIp == null) return [];
        try {
          final output = await Adb.sendSingleCommand('pm list packages', ip: _connectedIp!, port: _connectedPort);
            final List<String> packages = [];
            for (var line in output.split('\n')) {
                line = line.trim();
                // output from shell might not have newlines cleanly or might be raw
                if (line.startsWith('package:')) {
                    packages.add(line.substring(8).trim());
                } else if (line.contains('package:')) {
                   // regex?
                   final match = RegExp(r'package:([^\s]+)').firstMatch(line);
                   if (match != null) packages.add(match.group(1)!);
                }
            }
            return packages;
        } catch (e) {
          onLog("Mobile List Packages Error: $e", 'error');
          return [];
        }
      }

      try {
        final result = await runAdbCommand(['-s', serial, 'shell', 'pm', 'list', 'packages']);
        final output = result.stdout.toString();
        final List<String> packages = [];
        for (var line in output.split('\n')) {
            line = line.trim();
            if (line.startsWith('package:')) {
                packages.add(line.substring(8).trim());
            }
        }
        return packages;
      } catch (e) {
        onLog('Failed to list packages: $e', 'error');
        return [];
      }
  }
  
  Future<void> connectTcpIp(String serial) async {
     if (isMobile) return; // Cannot switch mode from mobile client
     await runAdbCommand(['-s', serial, 'tcpip', '5555']);
  }

  Future<void> connectWifi(String ip, {String port = '5555'}) async {
    if (isMobile) {
      // For mobile 'connect', checking connectivity is basically trying a command
      _connectedIp = ip;
      _connectedPort = int.tryParse(port) ?? 5555;
      try {
         await Adb.sendSingleCommand('echo init', ip: _connectedIp!, port: _connectedPort);
         onLog("Mobile ADB Client set to $_connectedIp:$_connectedPort", 'info');
      } catch (e) {
         _connectedIp = null;
         throw e;
      }
      return;
    }

    await runAdbCommand(['connect', '$ip:$port']);
  }

  Future<void> pairDevice(String ip, String port, String code) async {
    if (isMobile) {
       onLog("Pairing not supported in simple flutter_adb client yet.", 'error');
       return;
    }
    await runAdbCommand(['pair', '$ip:$port', code]);
  }

  Future<List<Map<String, String>>> getMdnsServices() async {
    if (isMobile) {
       // Use multicast_dns package
       final List<Map<String, String>> services = [];
       try {
         final MDnsClient client = MDnsClient();
         await client.start();
         
         // Look for _adb-tls-pairing._tcp.local and _adb._tcp.local ?
         // Usually it is _adb-tls-pairing._tcp for Wireless Debugging (pairing port)
         // And _adb._tcp for Connect port (if enabled via tcpip)
         
         // Helper for lookup so we can run both
         Future<void> lookup(String type) async {
            await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
                ResourceRecordQuery.serverPointer(type))) {
              
              await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
                  ResourceRecordQuery.service(ptr.domainName))) {
                
                await for (final IPAddressResourceRecord ip in client.lookup<IPAddressResourceRecord>(
                    ResourceRecordQuery.addressIPv4(srv.target))) {
                  
                  services.add({
                    'name': ptr.domainName,
                    'ip': ip.address.address,
                    'port': srv.port.toString(),
                    'type': type
                  });
                }
              }
            }
         }

         await Future.wait([
            lookup('_adb-tls-pairing._tcp.local'),
            lookup('_adb._tcp.local')
         ]);
         
         client.stop();
       } catch (e) {
         onLog("Mobile mDNS Error: $e", 'error');
       }
       return services;
    }

    try {
      final result = await runAdbCommand(['mdns', 'services']);
      final output = result.stdout.toString();
      final lines = output.split('\n');
      final List<Map<String, String>> services = [];

      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty || line.toLowerCase().startsWith('list of discovered')) continue;
        
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 3) continue;

        final instanceName = parts[0];
        // serviceType is parts[1] (e.g. _adb-tls-pairing._tcp.)
        final hostPart = parts.last; // ip:port

        String? ip;
        String? port;

        if (hostPart.contains(':')) {
           final split = hostPart.split(':');
           ip = split[0];
           port = split[1];
        }

        if (ip != null && port != null) {
          services.add({
            'name': instanceName,
            'ip': ip,
            'port': port,
          });
        }
      }
      return services;
    } catch (e) {
      onLog("MDNS scan failed: $e", 'error');
      return [];
    }
  }

  Future<List<String>> scanNetworkForPort(int port) async {
    try {
      final info = NetworkInfo();
      String? ip = await info.getWifiIP();
      
      // Fallback for some environments (simulators etc)
      if (ip == null) {
         final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: false);
         for (var interface in interfaces) {
           for (var addr in interface.addresses) {
             if (!addr.isLoopback) {
               ip = addr.address;
               break;
             }
           }
           if (ip != null) break;
         }
      }

      if (ip == null) {
        onLog("Could not determine local IP for scanning.", 'error');
        return [];
      }
      
      onLog("Scanning subnet of $ip for port $port ...", 'info');
      final String subnet = ip.substring(0, ip.lastIndexOf('.'));
      final List<Future<String?>> futures = [];

      // Scan 1-255
      for (int i = 1; i < 255; i++) {
        final String testIp = '$subnet.$i';
        // Skip our own IP if you want, but sometimes helpful to see
        futures.add(_checkPort(testIp, port));
      }

      final results = await Future.wait(futures);
      final found = results.whereType<String>().toList();
      onLog("Scan Complete. Found ${found.length} devices.", 'info');
      return found;

    } catch (e) {
      onLog("Network scan failed: $e", 'error');
      return [];
    }
  }

  Future<String?> _checkPort(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 300));
      socket.destroy();
      return ip;
    } catch (e) {
      return null;
    }
  }

  Future<void> takeScreenshot(String serial, String localPath) async {
    final remotePath = '/sdcard/screenshot.png';
    
    if (isMobile) {
       if (_connectedIp == null) return;
       try {
         await Adb.sendSingleCommand('screencap -p $remotePath', ip: _connectedIp!, port: _connectedPort);
         onLog("Downloading screenshot...", 'info');
         bool success = await Adb.downloadFile(remotePath, localPath, ip: _connectedIp!, port: _connectedPort);
         if (success) {
           await Adb.sendSingleCommand('rm $remotePath', ip: _connectedIp!, port: _connectedPort);
           onLog("Screenshot saved to $localPath", 'info');
         } else {
           onLog("Failed to download screenshot.", 'error');
         }
       } catch (e) {
         onLog("Screenshot exception: $e", 'error');
       }
       return;
    }

    await runAdbCommand(['-s', serial, 'shell', 'screencap', '-p', remotePath]);
    await runAdbCommand(['-s', serial, 'pull', remotePath, localPath]);
    await runAdbCommand(['-s', serial, 'shell', 'rm', remotePath]);
  }
  
  Future<Uint8List?> getScreenShotBytes(String serial) async {
    if (isMobile) {
       if (_connectedIp == null) return null;
       try {
         final tempDir = await getTemporaryDirectory();
         final start = DateTime.now().millisecondsSinceEpoch;
         final localPath = p.join(tempDir.path, 'temp_screen_$start.png');
         final remotePath = '/sdcard/temp_screen_$start.png';
         
         // 1. Cap
         await Adb.sendSingleCommand('screencap -p $remotePath', ip: _connectedIp!, port: _connectedPort);
         // 2. Pull
         bool success = await Adb.downloadFile(remotePath, localPath, ip: _connectedIp!, port: _connectedPort);
         // 3. Del (Fire and forget to speed up UI?)
         // No, we should clean up. But maybe async without await?
         Adb.sendSingleCommand('rm $remotePath', ip: _connectedIp!, port: _connectedPort);
         
         if (success) {
            final file = File(localPath);
            final bytes = await file.readAsBytes();
            await file.delete(); // Clean local
            return bytes;
         }
       } catch (e) {
         onLog("Mobile Stream error: $e", 'error');
       }
       return null;
    }

    try {
      // Use exec-out which dumps binary to stdout
      if (_adbPath == null) await init();
      final result = await Process.run(_adbPath!, ['-s', serial, 'exec-out', 'screencap', '-p'], stdoutEncoding: null);
      if (result.exitCode == 0) {
         return result.stdout as Uint8List;
      }
      return null;
    } catch (e) {
      onLog("Stream failed: $e", 'error');
      return null;
    }
  }

  Future<Process> startRecording(String serial) async {
     if (isMobile) {
        throw Exception("Recording not supported on mobile (client mode).");
     }

     if (_adbPath == null) await init();
     // Spawns a process that we have to kill later
     onLog("Starting screen recording...", 'info');
     return Process.start(_adbPath!, ['-s', serial, 'shell', 'screenrecord', '/sdcard/screenrecord.mp4']);
  }

  Future<void> pullRecording(String serial, String localPath) async {
    final remotePath = '/sdcard/screenrecord.mp4';

    if (isMobile) {
       if (_connectedIp == null) return;
       try {
         onLog("Downloading recording...", 'info');
         bool success = await Adb.downloadFile(remotePath, localPath, ip: _connectedIp!, port: _connectedPort);
         if (success) {
           await Adb.sendSingleCommand('rm $remotePath', ip: _connectedIp!, port: _connectedPort);
           onLog("Recording saved to $localPath", 'info');
         } else {
           onLog("Failed to download recording.", 'error');
         }
       } catch (e) {
         onLog("Pull recording exception: $e", 'error');
       }
       return;
    }
    
    await runAdbCommand(['-s', serial, 'pull', remotePath, localPath]);
    await runAdbCommand(['-s', serial, 'shell', 'rm', remotePath]);
  }
}
