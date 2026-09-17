import '../models/app_model.dart';

const recommendedAppIds = <String>[
  'smartspin2k',
  'grupetto',
  'material-files',
  'lawnchair',
  'aurora-store',
  'moonlight',
];

/// Returns one available app per recommended family in display order.
/// For a family with multiple compatible variants, prefer its highest priority.
List<AppModel> recommendedApps(Iterable<AppModel> compatibleApps) {
  final bestById = <String, AppModel>{};
  for (final app in compatibleApps) {
    final id = app.recommendationId;
    if (id == null || !recommendedAppIds.contains(id)) continue;
    final current = bestById[id];
    if (current == null ||
        app.recommendationPriority > current.recommendationPriority) {
      bestById[id] = app;
    }
  }
  return [
    for (final id in recommendedAppIds)
      if (bestById.containsKey(id)) bestById[id]!,
  ];
}
