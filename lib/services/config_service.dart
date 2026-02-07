import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/app_model.dart';

class ConfigService {
  Future<Map<String, AppModel>> loadApps(String? deviceAbi) async {
    try {
      final jsonString = await rootBundle.loadString('apps_config.json');
      final Map<String, dynamic> json = jsonDecode(jsonString);
      final appsMap = json['apps'] as Map<String, dynamic>;

      final apps = <String, AppModel>{};
      appsMap.forEach((key, value) {
        final app = AppModel.fromJson(key, value);
        
        // Filter based on ABI if provided
        if (deviceAbi != null) {
          if (deviceAbi == 'armeabi-v7a') {
            if (app.abi == 'armeabi-v7a') apps[key] = app;
          } else {
             // For newer devices (arm64), show arm64 apps
             if (app.abi == 'arm64-v8a') apps[key] = app;
          }
        } else {
          // If no device ABI known, maybe show all? Or wait? 
          // Python script shows all if no device? No, it waits for device.
          // But actually load_config defaults to get_device_abi() which might return None if no device.
          // If no ABI, Python script loads nothing or crashes?
          // Actually python script filters:
          // if device_abi == "armeabi-v7a": ... else: ...
          // So if abi is None, it goes to else -> arm64.
          
          if (app.abi == 'arm64-v8a') apps[key] = app; // Default to arm64
        }
      });
      return apps;
    } catch (e) {
      print("Error loading config: $e");
      return {};
    }
  }
}
