import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/images.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methodsChannel = MethodChannel('methods');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodsChannel, null);
    clearAllImageMemoryCaches();
  });

  testWidgets(
    'localOnly page with no local path shows offline-unavailable state without bridge calls',
    (tester) async {
      var bridgeCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodsChannel, (call) async {
        bridgeCalls++;
        final method = call.arguments is String ? call.arguments as String : '';
        fail('offline page must not invoke methods bridge: $method');
      });

      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: JMPageImage(
              42,
              'page.jpg',
              localOnly: true,
              width: 240,
              height: 320,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Offline image unavailable; download again'),
          findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      expect(bridgeCalls, 0);
    },
  );
}
