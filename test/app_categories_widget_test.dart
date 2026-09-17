import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:openpelo/models/app_model.dart';
import 'package:openpelo/providers/app_provider.dart';
import 'package:openpelo/widgets/app_list_widget.dart';

void main() {
  testWidgets(
    'category picker filters apps and recommended install has its own action',
    (tester) async {
      final provider = AppProvider();
      addTearDown(provider.dispose);
      provider.availableApps = {
        'Grupetto': AppModel(
          name: 'Grupetto',
          description: '',
          url: '',
          category: 'Fitness',
          recommendationId: 'grupetto',
        ),
        'Other files': AppModel(
          name: 'Other files',
          description: '',
          url: '',
          category: 'Files',
        ),
      };
      var installCalls = 0;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 350,
                child: AppListWidget(
                  onInstallRecommended: () => installCalls++,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Grupetto'), findsOneWidget);
      expect(find.text('Other files'), findsNothing);
      await tester.tap(find.text('Install all recommended (1)'));
      expect(installCalls, 1);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(provider.selectedAppCount, 1);
      await tester.tap(find.text('Recommended'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Files').last);
      await tester.pumpAndSettle();
      expect(find.text('Other files'), findsOneWidget);
      expect(find.text('Grupetto'), findsNothing);
      expect(find.text('Install all recommended (1)'), findsNothing);
      expect(provider.selectedAppCount, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
