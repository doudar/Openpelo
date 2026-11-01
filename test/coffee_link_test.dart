import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/widgets/coffee_link.dart';

void main() {
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  const label = 'Buy me a coffee (opens browser)';
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(launcher, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  Future<void> pumpLink(WidgetTester tester, Brightness brightness) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: const Scaffold(body: CoffeeLink()),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'logo opens the exact URL in an external browser: $brightness',
      (tester) async {
        MethodCall? request;
        binding.defaultBinaryMessenger.setMockMethodCallHandler(launcher, (
          call,
        ) async {
          request = call;
          return true;
        });
        await pumpLink(tester, brightness);
        expect(find.byTooltip(label), findsOneWidget);
        expect(
          tester.getSize(find.byType(IconButton)).width,
          greaterThanOrEqualTo(48),
        );
        await tester.tap(find.byTooltip(label));
        await tester.pumpAndSettle();
        expect(request?.method, 'launch');
        expect(
          request?.arguments['url'],
          'https://buymeacoffee.com/anthonydouv',
        );
        expect(request?.arguments['useWebView'], false);
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final throws in [false, true]) {
    testWidgets('browser failure offers a working copy link: throws=$throws', (
      tester,
    ) async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(launcher, (
        _,
      ) async {
        if (throws) throw PlatformException(code: 'NO_BROWSER');
        return false;
      });
      String? copied;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = call.arguments['text'] as String;
          }
          return null;
        },
      );
      await pumpLink(tester, Brightness.light);
      await tester.tap(find.byTooltip(label));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not open a browser.'), findsOneWidget);
      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      expect(copied, 'https://buymeacoffee.com/anthonydouv');
      expect(tester.takeException(), isNull);
    });
  }
}
