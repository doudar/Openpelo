import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/app_model.dart';

/// Catalog entries are sources; compatibility is derived from each APK.
class ConfigService {
  Future<Map<String, AppModel>> loadApps() async {
    final jsonString = await rootBundle.loadString('apps_config.json');
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    final apps = json['apps'] as Map<String, dynamic>;
    return apps.map(
      (name, value) => MapEntry(
        name,
        AppModel.fromJson(name, value as Map<String, dynamic>),
      ),
    );
  }
}
