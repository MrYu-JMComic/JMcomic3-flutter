import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Basic widget smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('JMcomic'),
        ),
      ),
    );

    expect(find.text('JMcomic'), findsOneWidget);
  });
}
