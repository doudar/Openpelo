import 'dart:convert';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/adb_service.dart';
import '../services/config_service.dart';
import '../models/app_model.dart';
import '../models/device_model.dart';
import 'package:intl/intl.dart';

class LogEntry {
  final String timestamp;
  final String message;
  final String tag;
  LogEntry(this.timestamp, this.message, this.tag);
}

class AppProvider with ChangeNotifier {
  final AdbService _adbService;
  final ConfigService _configService = ConfigService();
  static final Uri _openpeloLatestReleaseApiUri =
      Uri.https('api.github.com', '/repos/doudar/openpelo/releases/latest');
  static final Uri _openpeloReleasesPageUri =
      Uri.parse('https://github.com/doudar/openpelo/releases/');
  static const Map<String, String> _githubApiHeaders = {
    'User-Agent': 'Openpelo/1.0',
    'Accept': 'application/vnd.github+json',
  };
  
  List<LogEntry> logs = [];
  List<DeviceModel> devices = [];
  Map<String, AppModel> availableApps = {};
  DeviceModel? selectedDevice;
  String statusMessage = "Checking device connection...";
  bool isBusy = false;
  Timer? _heartbeatTimer;
  Process? _recordingProcess;
  bool isRecording = false;
  String? _saveLocation;
  bool isCheckingForUpdate = false;
  String? currentAppVersion;
  String? latestAppVersion;
  Uri latestReleasePageUrl = _openpeloReleasesPageUri;
  String? updateCheckError;

  AppProvider() : _adbService = AdbService(onLog: (m, t) {}) {
    // Re-initialize AdbService with actual log handler
    // But we need 'this' which we can't use in initializer.
    // So we use a wrapper or init method.
  }

  void init() {
    _adbService.onLog = _onLog;
    _adbService.init().then((_) {
      _startHeartbeat();
      _checkDevices();
    });
    _loadSaveLocation();
    _loadCurrentAppVersion();
    checkForUpdates();
  }

  static const int _maxLogLines = 300;

  void _onLog(String message, String tag) {
    final time = DateFormat('HH:mm:ss').format(DateTime.now());
    logs.add(LogEntry('[$time]', message, tag));
    if (logs.length > _maxLogLines) {
      logs = logs.sublist(logs.length - _maxLogLines);
    }
    notifyListeners();
  }

  void _setBusy(bool value) {
    isBusy = value;
    notifyListeners();
  }

  bool get isUpdateAvailable {
    final current = currentAppVersion;
    final latest = latestAppVersion;
    if (current == null || latest == null) return false;
    return _compareVersions(latest, current) > 0;
  }

  Future<void> openReleasesPage() async {
    if (!await launchUrl(latestReleasePageUrl, mode: LaunchMode.externalApplication)) {
      _onLog("Could not open releases page: $latestReleasePageUrl", 'error');
    }
  }

  Future<void> checkForUpdates() async {
    if (isCheckingForUpdate) return;

    isCheckingForUpdate = true;
    updateCheckError = null;
    notifyListeners();

    try {
      currentAppVersion ??= await _getCurrentAppVersion();

      final response = await _httpGetWithWindowsTlsFallback(
        _openpeloLatestReleaseApiUri,
        headers: _githubApiHeaders,
      );

      if (response.statusCode != HttpStatus.ok) {
        updateCheckError =
            'Failed to check updates (HTTP ${response.statusCode}).';
        return;
      }

      final Map<String, dynamic> release =
          jsonDecode(response.body) as Map<String, dynamic>;
      final tag = (release['tag_name'] ?? '').toString().trim();
      final name = (release['name'] ?? '').toString().trim();
      final htmlUrl = (release['html_url'] ?? '').toString().trim();

      final resolvedLatest = tag.isNotEmpty
          ? tag
          : (name.isNotEmpty ? name : '');

      if (resolvedLatest.isEmpty) {
        updateCheckError = 'Could not determine latest release version.';
        return;
      }

      latestAppVersion = _normalizeVersion(resolvedLatest);
      if (htmlUrl.isNotEmpty) {
        latestReleasePageUrl = Uri.parse(htmlUrl);
      }
    } catch (e) {
      updateCheckError = 'Update check failed: $e';
      _onLog(updateCheckError!, 'error');
    } finally {
      isCheckingForUpdate = false;
      notifyListeners();
    }
  }

  Future<void> _loadCurrentAppVersion() async {
    if (currentAppVersion != null) return;

    try {
      currentAppVersion = await _getCurrentAppVersion();
    } catch (e) {
      _onLog('Unable to read current app version: $e', 'error');
    } finally {
      notifyListeners();
    }
  }

  Future<String> _getCurrentAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return _normalizeVersion(packageInfo.version);
  }

  String _normalizeVersion(String rawVersion) {
    var value = rawVersion.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }

    final match = RegExp(r'\d+(?:\.\d+){0,3}').firstMatch(value);
    return match?.group(0) ?? value;
  }

  int _compareVersions(String a, String b) {
    final aParts = _normalizeVersion(a)
        .split('.')
        .where((p) => p.isNotEmpty)
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final bParts = _normalizeVersion(b)
        .split('.')
        .where((p) => p.isNotEmpty)
        .map((p) => int.tryParse(p) ?? 0)
        .toList();

    final length = aParts.length > bParts.length ? aParts.length : bParts.length;
    for (var index = 0; index < length; index++) {
      final aPart = index < aParts.length ? aParts[index] : 0;
      final bPart = index < bParts.length ? bParts[index] : 0;

      if (aPart > bPart) return 1;
      if (aPart < bPart) return -1;
    }

    return 0;
  }

  void _loadSaveLocation() async {
    final docDir = await getApplicationDocumentsDirectory();
    _saveLocation = p.join(docDir.path, "OpenPelo");
    final dir = Directory(_saveLocation!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    notifyListeners();
  }
  
  String get saveLocation => _saveLocation ?? "";

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!isBusy) {
        _checkDevices(silent: true);
      }
    });
  }

  Future<void> _checkDevices({bool silent = false}) async {
    final newDevices = await _adbService.getConnectedDevices();
    
    // Simple check if changes to avoid unnecessary re-renders/logs
    // In a real app we might want deep equality check
    if (newDevices.length != devices.length || 
        (newDevices.isNotEmpty && devices.isNotEmpty && newDevices[0].serial != devices[0].serial)) {
        devices = newDevices;
        
        if (devices.isEmpty) {
          statusMessage = "❌ No device detected. Please connect your device and enable USB debugging.";
          selectedDevice = null;
          availableApps = {};
        } else {
          // Select first if none selected or previous selection gone
          if (selectedDevice == null || !devices.any((d) => d.serial == selectedDevice!.serial)) {
             // Prefer wifi
             selectedDevice = devices.firstWhere((d) => d.transport == 'wifi', orElse: () => devices.first);
          } else {
             // Update selected device info
             selectedDevice = devices.firstWhere((d) => d.serial == selectedDevice!.serial);
          }
          
          statusMessage = "✅ Connected to ${selectedDevice!.displayName}";
          if (!silent) _onLog(statusMessage, 'status');
          _loadApps();
        }
        notifyListeners();
    }
  }

  Future<void> _loadApps() async {
    if (selectedDevice == null) return;
    availableApps = await _configService.loadApps(selectedDevice!.abi);
    notifyListeners();
  }

  void selectDevice(DeviceModel device) {
    selectedDevice = device;
    statusMessage = "✅ Connected to ${device.displayName}";
    _loadApps();
    notifyListeners();
  }

  Future<void> refresh() async {
    await _checkDevices();
  }

  Future<String> _resolveDownloadUrl(String url, String? packageName) async {
    try {
      final uri = Uri.parse(url);
      if (uri.host == 'github.com' && uri.pathSegments.length >= 2) {
        final owner = uri.pathSegments[0];
        final repo = uri.pathSegments[1];
        if (uri.pathSegments.contains('releases') && uri.pathSegments.contains('latest')) {
          final apiUrl = Uri.https('api.github.com', '/repos/$owner/$repo/releases/latest');
          return _resolveDownloadUrl(apiUrl.toString(), packageName);
        }
      }
      if (uri.host.contains('api.github.com')) {
         _onLog("Resolving GitHub API URL...", 'info');
         final response = await _httpGetWithWindowsTlsFallback(
           uri,
           headers: _githubApiHeaders,
         );

         if (response.statusCode == 200) {
            final json = jsonDecode(response.body);
            final List<dynamic> assets = json['assets'] ?? [];
            if (assets.isEmpty) return url;

            // 1. Try exact match
            if (packageName != null) {
              final exact = assets.firstWhere((a) => a['name'] == packageName, orElse: () => null);
              if (exact != null) return exact['browser_download_url'];
            }

            // 2. Try .apk
            final apk = assets.firstWhere((a) => a['name'].toString().toLowerCase().endsWith('.apk'), orElse: () => null);
            if (apk != null) return apk['browser_download_url'];

            // 3. Fallback
            return assets.first['browser_download_url'];
         }
      }
      return url;
    } catch (e) {
      _onLog("Error resolving URL: $e", 'error');
      return url;
    }
  }

  Map<String, String> _buildDownloadHeaders(Uri uri) {
    final headers = <String, String>{
      // Some hosts block requests without a UA; keep this stable for all downloads.
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
    };

    if (uri.host.contains('teslacoilapps.com')) {
      headers['Referer'] = 'https://teslacoilapps.com/';
    }

    return headers;
  }

  Future<bool> _downloadToFile(Uri uri, File file) async {
    final headers = _buildDownloadHeaders(uri);
    final client = HttpClient();
    client.userAgent = headers['User-Agent'];
    try {
      final request = await client.getUrl(uri);
      headers.forEach(request.headers.add);
      request.followRedirects = true;
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        _onLog("Failed to download (Status: ${response.statusCode})", 'error');
        return false;
      }

      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }

      final sink = file.openWrite();
      await response.pipe(sink);
      await sink.flush();
      await sink.close();
      return true;
    } catch (e) {
      if (Platform.isWindows && _isWindowsTlsHandshakeError(e)) {
        _onLog("TLS handshake failed. Retrying download with Windows curl...", 'info');
        return _downloadToFileWithWindowsCurl(uri, file, headers: headers);
      }
      _onLog("Download error: $e", 'error');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  bool _isWindowsTlsHandshakeError(Object error) {
    if (error is HandshakeException) {
      return true;
    }

    final text = error.toString().toLowerCase();
    return text.contains('handshakeexception') ||
        text.contains('ssl') ||
        text.contains('tls') ||
        text.contains('certificate_verify_failed') ||
        text.contains('unable to get local issuer certificate');
  }

  Future<http.Response> _httpGetWithWindowsTlsFallback(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    try {
      return await http.get(uri, headers: headers);
    } catch (e) {
      if (Platform.isWindows && _isWindowsTlsHandshakeError(e)) {
        _onLog("TLS handshake failed. Retrying request with Windows curl...", 'info');
        final body = await _httpGetBodyWithWindowsCurl(uri, headers: headers);
        if (body != null) {
          return http.Response(body, HttpStatus.ok);
        }
      }
      rethrow;
    }
  }

  List<String> _buildWindowsCurlArgs(
    Uri uri, {
    required Map<String, String> headers,
    String? outputPath,
  }) {
    final args = <String>[
      '--location',
      '--silent',
      '--show-error',
      '--fail',
      '--max-redirs',
      '5',
    ];

    headers.forEach((key, value) {
      args.addAll(['-H', '$key: $value']);
    });

    if (outputPath != null) {
      args.addAll(['-o', outputPath]);
    }

    args.add(uri.toString());
    return args;
  }

  Future<String?> _httpGetBodyWithWindowsCurl(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    if (!Platform.isWindows) return null;

    try {
      final args = _buildWindowsCurlArgs(uri, headers: headers);

      final result = await Process.run('curl.exe', args);
      if (result.exitCode == 0) {
        return result.stdout.toString();
      }

      _onLog(
        "Windows curl request failed (${result.exitCode}): ${result.stderr}",
        'error',
      );
      return null;
    } catch (e) {
      _onLog("Windows curl request error: $e", 'error');
      return null;
    }
  }

  Future<bool> _downloadToFileWithWindowsCurl(
    Uri uri,
    File file, {
    required Map<String, String> headers,
  }) async {
    try {
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }

      final args = _buildWindowsCurlArgs(
        uri,
        headers: headers,
        outputPath: file.path,
      );

      final result = await Process.run('curl.exe', args);
      if (result.exitCode == 0 && await file.exists()) {
        return true;
      }

      _onLog(
        "Windows curl download failed (${result.exitCode}): ${result.stderr}",
        'error',
      );
      return false;
    } catch (e) {
      _onLog("Windows curl download error: $e", 'error');
      return false;
    }
  }

  String? _extractConflictingPackageFromInstallOutput(
    String output,
    String? packageHint,
  ) {
    final match = RegExp(r'Package\s+([a-zA-Z0-9_\.]+)\s+signatures')
        .firstMatch(output);
    return match?.group(1) ?? packageHint;
  }

  Future<String> _resolveInstallConflictIfNeeded({
    required String output,
    required String appName,
    required String? packageHint,
    required Future<bool> Function(String appName) onConfirmReinstall,
    required Future<String> Function() retryInstall,
  }) async {
    if (!output.contains('INSTALL_FAILED_UPDATE_INCOMPATIBLE')) {
      return output;
    }

    final conflictingPkg = _extractConflictingPackageFromInstallOutput(
      output,
      packageHint,
    );
    if (conflictingPkg == null || selectedDevice == null) {
      return output;
    }

    final shouldUninstall = await onConfirmReinstall(appName);
    if (!shouldUninstall) {
      return output;
    }

    _onLog("Uninstalling old version of $appName...", 'info');
    await _adbService.uninstallPackage(selectedDevice!.serial, conflictingPkg);
    _onLog("Retrying install of $appName...", 'info');
    return retryInstall();
  }

  Future<void> installSelectedApps(Future<bool> Function(String appName) onConfirmReinstall) async {
    if (selectedDevice == null) return;
    final appsToInstall = availableApps.values.where((a) => a.isSelected).toList();
    if (appsToInstall.isEmpty) return;

    _setBusy(true);
    
    try {
      for (final app in appsToInstall) {
        
        final downloadUrl = await _resolveDownloadUrl(app.url, app.package);
        
          final downloadUri = Uri.parse(downloadUrl);
          _onLog("Downloading ${app.name} from $downloadUrl...", 'info');
          final tempDir = await getTemporaryDirectory();
          // Ensure unique name or use package name to avoid conflicts/caching if needed
          final filename = app.package ?? "${app.name.replaceAll(' ', '_')}.apk";
          final apkPath = p.join(tempDir.path, filename);
          final file = File(apkPath);
          final ok = await _downloadToFile(downloadUri, file);
          if (ok) {
            _onLog("Installing ${app.name}...", 'info');
            String output = await _adbService.installApk(selectedDevice!.serial, apkPath);

            output = await _resolveInstallConflictIfNeeded(
              output: output,
              appName: app.name,
              packageHint: app.package,
              onConfirmReinstall: onConfirmReinstall,
              retryInstall: () => _adbService.installApk(selectedDevice!.serial, apkPath),
            );

           if (output.contains('Success')) {
             _onLog("Successfully installed ${app.name}", 'info');
           } else {
             _onLog("Error installing ${app.name}: $output", 'error');
           }
        }
      }
    } catch (e) {
      _onLog("Installation failed: $e", 'error');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> installLocalApk(Future<bool> Function(String appName) onConfirmReinstall) async {
    if (selectedDevice == null) return;
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['apk'],
    );

    if (result != null) {
      final path = result.files.single.path;
      if (path != null) {
        _setBusy(true);
        try {
          final filename = p.basename(path);
          _onLog("Installing local APK: $filename", 'info');
          String output = await _adbService.installApk(selectedDevice!.serial, path);

          output = await _resolveInstallConflictIfNeeded(
            output: output,
            appName: filename,
            packageHint: null,
            onConfirmReinstall: onConfirmReinstall,
            retryInstall: () => _adbService.installApk(selectedDevice!.serial, path),
          );

          if (output.contains('Success')) {
            _onLog("Successfully installed local APK", 'info');
          } else {
            _onLog("Failed install: $output", 'error');
          }
        } catch (e) {
           _onLog("Failed install: $e", 'error');
        } finally {
          _setBusy(false);
        }
      }
    }
  }

  void toggleRecording() async {
    if (selectedDevice == null) return;
    
    if (isRecording) {
      // Stop recording
      if (_recordingProcess != null) {
         _recordingProcess!.kill(ProcessSignal.sigint); // Send SIGINT to stop gracefully if possible? 
         // Screenrecord on android usually stops on SIGINT (CTRL+C).
         // Process.kill uses SIGTERM by default. 
         // Let's try sending literal arbitrary signal or just kill.
         _onLog("Stopping recording...", 'info');
         // Wait a bit?
         await Future.delayed(Duration(seconds: 1));
      }
      isRecording = false;
      notifyListeners();
      
      // Pull
      _setBusy(true);
      try {
         final date = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
         final filename = "recording_$date.mp4";
         final savePath = p.join(saveLocation, filename);
         await _adbService.pullRecording(selectedDevice!.serial, savePath);
         _onLog("Recording saved to $savePath", 'info');
      } catch (e) {
         _onLog("Failed to save recording: $e", 'error');
      } finally {
        _setBusy(false);
      }

    } else {
      try {
        _recordingProcess = await _adbService.startRecording(selectedDevice!.serial);
        isRecording = true;
        _onLog("Recording started...", 'info');
        notifyListeners();
      } catch (e) {
        _onLog("Failed to start recording: $e", 'error');
      }
    }
  }

  Future<void> takeScreenshot() async {
     if (selectedDevice == null) return;
     try {
       final date = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
       final filename = "screenshot_$date.png";
       final savePath = p.join(saveLocation, filename);
       await _adbService.takeScreenshot(selectedDevice!.serial, savePath);
       _onLog("Screenshot saved to $savePath", 'info');
     } catch (e) {
       _onLog("Screenshot failed: $e", 'error');
     }
  }

  Future<Uint8List?> getScreenShotBytes() async {
    if (selectedDevice == null) return null;
    return await _adbService.getScreenShotBytes(selectedDevice!.serial);
  }

  Future<void> chooseSaveLocation() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      _saveLocation = selectedDirectory;
      notifyListeners();
    }
  }

  Future<List<Map<String, String>>> loadGuide(String filename) async {
    try {
      final jsonString = await rootBundle.loadString(filename);
      final json = jsonDecode(jsonString);
      final List<dynamic> steps = json['steps'];
      return steps.map((s) => {
        'title': s['title'].toString(),
        'description': s['description'].toString()
      }).toList();
    } catch (e) {
      _onLog("Error loading guide $filename: $e", 'error');
      return [];
    }
  }

  Future<void> connectWireless(String ip, String port, String code, String connectionPort) async {
    _setBusy(true);
    try {
      if (code.isNotEmpty && port.isNotEmpty) {
        _onLog("Pairing with $ip:$port...", 'info');
        await _adbService.pairDevice(ip, port, code);
        _onLog("Pairing command sent.", 'info');
      }
      
      _onLog("Connecting to $ip:$connectionPort...", 'info');
      await _adbService.connectWifi(ip, port: connectionPort);
      _onLog("Connection command sent.", 'info');
      
      // Wait a bit and check devices
      await Future.delayed(const Duration(seconds: 2));
      await _checkDevices();
    } catch (e) {
      _onLog("Wireless connection failed: $e", 'error');
    } finally {
      _setBusy(false);
    }
  }

  /// Enable wireless ADB on a USB-connected device.
  /// Switches it to tcpip mode, discovers its IP, and connects wirelessly.
  Future<String?> enableWirelessViaUsb(String serial) async {
    _setBusy(true);
    try {
      _onLog("Switching $serial to TCP/IP mode on port 5555...", 'info');
      await _adbService.connectTcpIp(serial);
      
      // Give the device a moment to restart in tcpip mode
      await Future.delayed(const Duration(seconds: 2));
      
      _onLog("Querying device IP address...", 'info');
      final ip = await _adbService.getDeviceIp(serial);
      if (ip == null || ip.isEmpty) {
        _onLog("Could not determine device IP. Make sure the device is connected to WiFi.", 'error');
        return null;
      }
      
      _onLog("Device IP: $ip. Connecting wirelessly...", 'info');
      await _adbService.connectWifi(ip, port: '5555');
      
      _onLog("Wireless connection established. You can now unplug the USB cable.", 'status');
      
      // Wait a bit and refresh device list
      await Future.delayed(const Duration(seconds: 2));
      await _checkDevices();
      
      return ip;
    } catch (e) {
      _onLog("Failed to enable wireless ADB via USB: $e", 'error');
      return null;
    } finally {
      _setBusy(false);
    }
  }

  /// Run developer option toggles on the selected device.
  /// Returns a map of option name → success/failure.
  Future<Map<String, bool>> enableDeveloperSettings({
    required String serial,
    bool wirelessDebugging = false,
    bool stayAwake = false,
  }) async {
    _setBusy(true);
    final results = <String, bool>{};
    try {
      if (wirelessDebugging) {
        results['Wireless Debugging'] = await _adbService.enableWirelessDebugging(serial);
      }
      if (stayAwake) {
        results['Stay Awake While Charging'] = await _adbService.enableStayAwake(serial);
      }
    } catch (e) {
      _onLog("Error enabling developer settings: $e", 'error');
    } finally {
      _setBusy(false);
    }
    return results;
  }

  /// Get installed launchers on the selected device.
  Future<List<Map<String, String>>> getInstalledLaunchers() async {
    if (selectedDevice == null) return [];
    _setBusy(true);
    try {
      return await _adbService.getInstalledLaunchers(selectedDevice!.serial);
    } catch (e) {
      _onLog("Error getting launchers: $e", 'error');
      return [];
    } finally {
      _setBusy(false);
    }
  }

  /// Open the app info settings page for a specific package on the device.
  Future<bool> openAppSettings(String packageName) async {
    if (selectedDevice == null) return false;
    try {
      return await _adbService.openAppSettings(selectedDevice!.serial, packageName);
    } catch (e) {
      _onLog("Error opening app settings: $e", 'error');
      return false;
    }
  }

  /// Set the device display rotation (0-3).
  Future<bool> setRotation(int rotation) async {
    if (selectedDevice == null) return false;
    try {
      return await _adbService.setRotation(selectedDevice!.serial, rotation);
    } catch (e) {
      _onLog("Error setting rotation: $e", 'error');
      return false;
    }
  }

  /// Get the current device display rotation (0-3).
  Future<int> getRotation() async {
    if (selectedDevice == null) return 0;
    try {
      return await _adbService.getRotation(selectedDevice!.serial);
    } catch (_) {
      return 0;
    }
  }

  /// Get whether auto-rotation is enabled on the device.
  Future<bool> getAutoRotation() async {
    if (selectedDevice == null) return false;
    try {
      return await _adbService.getAutoRotation(selectedDevice!.serial);
    } catch (_) {
      return false;
    }
  }

  /// Enable or disable auto-rotation on the device.
  Future<bool> setAutoRotation(bool enabled) async {
    if (selectedDevice == null) return false;
    try {
      return await _adbService.setAutoRotation(selectedDevice!.serial, enabled);
    } catch (e) {
      _onLog("Error setting auto-rotation: $e", 'error');
      return false;
    }
  }

  Future<List<Map<String, String>>> scanForWirelessDevices({int? port}) async {
    _setBusy(true);
    List<Map<String, String>> devices = [];
    try {
       _onLog("Scanning for wireless devices (mDNS)...", 'info');
       devices = await _adbService.getMdnsServices();

       // If mDNS scan fails to find devices or if a port is explicitly requested (scan specific mode)
       // We scan the local subnet.
       // Note: mDNS usually finds the pairing service (port ~30000-45000) or connect service (5555).
       // If empty, let's try to scan port 5555 on the subnet.
       
       if (devices.isEmpty || port != null) {
          int targetPort = port ?? 5555;
          _onLog("Scanning subnet for port $targetPort...", 'info');
          List<String> foundIps = await _adbService.scanNetworkForPort(targetPort);
          for (var ip in foundIps) {
             devices.add({
               'name': 'Scanned Device ($ip)',
               'ip': ip,
               'port': targetPort.toString()
             });
          }
       } else {
         _onLog("Found ${devices.length} devices.", 'info');
       }
       return devices;
    } catch (e) {
      _onLog("Scan error: $e", 'error');
      return devices;
    } finally {
       _setBusy(false);
    }
  }

  Future<List<String>> scanPelotonPackages() async {
    if (selectedDevice == null) return [];
    _setBusy(true);
    try {
      _onLog("Scanning for Peloton packages...", 'info');
      final allPackages = await _adbService.listPackages(selectedDevice!.serial);
      
      // Filter logic from python script:
      // 'peloton' in name AND not 'affernet' AND not 'input' AND not 'sensor'
      final pelotonPackages = allPackages.where((pkg) {
        final lower = pkg.toLowerCase();
        return lower.contains('peloton') && 
               !lower.contains('affernet') && 
               !lower.contains('input') && 
               !lower.contains('sensor');
      }).toList();
      
      pelotonPackages.sort();
      return pelotonPackages;
    } catch (e) {
      _onLog("Scan failed: $e", 'error');
      return [];
    } finally {
      _setBusy(false);
    }
  }

  Future<Map<String, int>> uninstallPelotonPackages(List<String> packages) async {
    if (selectedDevice == null) return {'success': 0, 'fail': 0};

    _setBusy(true);
    
    int success = 0;
    int fail = 0;

    try {
      for (final pkg in packages) {
         _onLog("Uninstalling $pkg...", 'info');
         String output = await _adbService.uninstallPackage(selectedDevice!.serial, pkg);
         
         if (output.contains('Success')) {
           success++;
           _onLog("Successfully uninstalled $pkg", 'status');
         } else {
           _onLog("Standard uninstall failed, trying user 0 override...", 'info');
           output = await _adbService.uninstallPackageUser0(selectedDevice!.serial, pkg);
           if (output.contains('Success')) {
             success++;
             _onLog("Successfully uninstalled $pkg (user 0)", 'status');
           } else {
             fail++;
             _onLog("Failed to uninstall $pkg: $output", 'error');
           }
         }
      }
    } catch (e) {
      _onLog("Batch uninstall error: $e", 'error');
    } finally {
      _setBusy(false);
    }
    
    return {'success': success, 'fail': fail};
  }

  void openSaveLocation() {
    if (_saveLocation != null) {
       // use url_launcher or process to open folder
       // url_launcher 'file:$path' works on some OS
       Process.run(Platform.isWindows ? 'explorer' : 'open', [_saveLocation!]); 
    }
  }
}
