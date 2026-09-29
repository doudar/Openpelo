import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/models/app_model.dart';
import 'package:openpelo/services/app_categories.dart';

AppModel app(String name, String? recommendationId, {int priority = 0}) =>
    AppModel(
      name: name,
      description: '',
      url: '',
      recommendationId: recommendationId,
      recommendationPriority: priority,
    );

void main() {
  test('recommendations use fixed display order and deduplicate variants', () {
    final results = recommendedApps([
      app('Moonlight', 'moonlight'),
      app('Google TTS Legacy', 'google-tts'),
      app('Google TTS', 'google-tts', priority: 1),
      app('Old Lawnchair', 'lawnchair'),
      app('Unrelated', null),
      app('Aurora', 'aurora-store'),
      app('Material Files', 'material-files'),
      app('New Lawnchair', 'lawnchair', priority: 1),
      app('Grupetto', 'grupetto'),
      app('SmartSpin2k', 'smartspin2k'),
    ]);

    expect(results.map((app) => app.name), [
      'SmartSpin2k',
      'Grupetto',
      'Material Files',
      'New Lawnchair',
      'Aurora',
      'Moonlight',
      'Google TTS',
    ]);
  });

  test('uses available legacy variants when modern variants are absent', () {
    final results = recommendedApps([
      app('Old Lawnchair', 'lawnchair'),
      app('Google TTS Legacy', 'google-tts'),
      app('Unrelated', null),
    ]);

    expect(results.map((app) => app.name), [
      'Old Lawnchair',
      'Google TTS Legacy',
    ]);
  });
}
