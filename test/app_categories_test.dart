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
    ]);
  });

  test('uses available legacy Lawnchair when modern variant is absent', () {
    final results = recommendedApps([
      app('Old Lawnchair', 'lawnchair'),
      app('Unrelated', null),
    ]);

    expect(results.map((app) => app.name), ['Old Lawnchair']);
  });
}
