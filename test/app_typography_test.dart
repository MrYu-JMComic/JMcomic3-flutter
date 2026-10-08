import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/theme.dart' as app_theme;

void main() {
  for (final dark in [false, true]) {
    final theme = dark ? app_theme.darkTheme : app_theme.lightTheme;
    test('app typography is compact and regular ${dark ? 'dark' : 'light'}',
        () {
      expect(theme.textTheme.titleLarge!.fontSize, 19);
      expect(theme.textTheme.titleLarge!.fontWeight, FontWeight.w500);
      expect(theme.textTheme.titleMedium!.fontSize, 16);
      expect(theme.textTheme.titleMedium!.fontWeight, FontWeight.w400);
      expect(theme.textTheme.titleSmall!.fontSize, 14);
      expect(theme.textTheme.titleSmall!.fontWeight, FontWeight.w400);
      expect(theme.textTheme.bodyLarge!.fontSize, 15);
      expect(theme.textTheme.bodyMedium!.fontSize, 14);
      expect(theme.textTheme.bodySmall!.fontSize, 12);
      expect(theme.textTheme.bodyMedium!.fontWeight, FontWeight.w400);
      expect(theme.textTheme.labelSmall!.fontSize, greaterThanOrEqualTo(11));
      expect(theme.appBarTheme.titleTextStyle!.fontWeight, FontWeight.w400);
      expect(theme.tabBarTheme.labelStyle!.fontWeight, FontWeight.w400);
    });

    testWidgets(
        'smaller app typography retains system text scaling ${dark ? 'dark' : 'light'}',
        (tester) async {
      Widget host(double scale) => MaterialApp(
            theme: theme,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                  body: Builder(
                      builder: (context) => Text(
                            'Typography',
                            key: const ValueKey('scaled-text'),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ))),
            ),
          );
      final text = find.byKey(const ValueKey('scaled-text'));
      await tester.pumpWidget(host(1));
      final normal = tester.getSize(text);
      await tester.pumpWidget(host(2));
      final enlarged = tester.getSize(text);
      expect(enlarged.height, closeTo(normal.height * 2, 1));
      // Font hinting rounds glyph metrics; scaling must remain effective,
      // but its rendered width need not be an exact integer multiple.
      expect(enlarged.width / normal.width, closeTo(2, .05));
      expect(tester.takeException(), isNull);
    });
  }
}
