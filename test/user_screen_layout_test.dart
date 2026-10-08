import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/daily_sign.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/configs/theme.dart' as app_theme;
import 'package:jmcomic3/configs/versions.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/avatar.dart';
import 'package:jmcomic3/screens/user_screen.dart';

const _methodsChannel = MethodChannel('methods');
const _previewKey = ValueKey('profile-layout-preview');
const _username = 'A reader with a long account name';
final _saveScreenshots = Platform.environment['LAYOUT_SCREENSHOTS'] == '1';
late Map<String, Object> _selfInfo;
late List<String> _requests;

Widget _profile({double textScale = 1, bool dark = false}) {
  return MaterialApp(
    theme: app_theme.lightTheme,
    darkTheme: app_theme.darkTheme,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    locale: const Locale('en'),
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: RepaintBoundary(key: _previewKey, child: child!),
    ),
    home: const UserScreen(),
  );
}

Future<void> _loadProfile(WidgetTester tester) async {
  // The avatar sentinel avoids loading an external profile photo. All account
  // state still comes through the same public initialization used by the app.
  await initLogin(tester.element(find.byType(UserScreen)));
  await tester.runAsync(() => initVersion());
  await tester.pumpAndSettle();
  expect(loginStatus, LoginStatus.loginSuccess);
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_saveScreenshots) return;
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_previewKey),
  );
  await tester.runAsync(() async {
    final bitmap = await boundary.toImage(pixelRatio: 1);
    final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/layout-validation/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    bitmap.dispose();
  });
}

Future<void> _loadPreviewFonts(WidgetTester tester) async {
  if (!_saveScreenshots) return;
  await tester.runAsync(() async {
    final font = File('C:/Windows/Fonts/segoeui.ttf');
    if (await font.exists()) {
      final bytes = ByteData.sublistView(await font.readAsBytes());
      for (final family in ['LayoutPreview', 'Roboto']) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
    final config =
        jsonDecode(await File('.dart_tool/package_config.json').readAsString())
            as Map;
    final sdk = Uri.parse(config['flutterRoot'] as String).toFilePath();
    final icons = File(
        '$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
    if (await icons.exists()) {
      await (FontLoader('MaterialIcons')
            ..addFont(
                Future.value(ByteData.sublistView(await icons.readAsBytes()))))
          .load();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dailySignStatus = DailySignStatus.unchecked;
    _requests = [];
    _selfInfo = {
      'uid': 42,
      'username': _username,
      'email': 'reader.with.long.email@example.invalid',
      'emailverified': 'yes',
      'photo': '?v=0?v=',
      'fname': 'A long nickname that should wrap at narrow widths',
      'gender': 'female',
      'message': 'A long signature keeps all profile details readable.',
      'coin': 987654321,
      'album_favorites': 8,
      's': '',
      'level_name': 'A very long membership level',
      'level': 22,
      'nextLevelExp': 1000,
      'exp': '350',
      'expPercent': .35,
      'badges': ['one', 'two'],
      'album_favorites_max': 100,
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_methodsChannel, (call) async {
      final request =
          jsonDecode(call.arguments as String) as Map<String, dynamic>;
      final method = request['method'];
      _requests.add(method as String);
      final Object response;
      switch (method) {
        case 'pre_login':
          response = {
            'pre_set': true,
            'pre_login': true,
            'message': '',
            'self_info': _selfInfo,
          };
          break;
        case 'favorite':
          response = {
            'total': 0,
            'count': 0,
            'list': <Object>[],
            'folder_list': <Object>[],
          };
          break;
        case 'pro_info_all':
          response = {
            'pro_info_af': {'is_pro': true, 'expire': 4102444800},
            'pro_info_pat': {'is_pro': true},
          };
          break;
        default:
          response = '';
      }
      return jsonEncode({
        'error_message': '',
        'response_data': response is String ? response : jsonEncode(response),
      });
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_methodsChannel, null);
    dailySignStatus = DailySignStatus.unchecked;
  });

  testWidgets('signed-in profile wraps at 320px with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _loadPreviewFonts(tester);
    await tester.pumpWidget(_profile(textScale: 2));
    await _loadProfile(tester);
    expect(find.text(_username), findsOneWidget);
    expect(find.text('reader.with.long.email@example.invalid'), findsOneWidget);
    expect(find.text('Lv.22'), findsOneWidget);
    expect(find.text('A very long membership level'), findsOneWidget);
    expect(find.text('A long nickname that should wrap at narrow widths'),
        findsOneWidget);
    expect(find.text('A long signature keeps all profile details readable.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('profile-statistics-row')), findsNothing);
    final progress = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(progress.value, .35);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'profile-mobile-large-text');

    for (final label in [
      'Manual Sign-in',
      'Not checked',
      'Favorites',
      'History',
      'Download List',
      'Comments',
    ]) {
      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget, reason: label);
      expect(tester.takeException(), isNull, reason: label);
    }

    dailySignStatus = DailySignStatus.checking;
    dailySignEvent.broadcast();
    await tester.pump();
    await tester.ensureVisible(find.text('Signing...'));
    await tester.pumpAndSettle();
    final signButton = tester.widget<FilledButton>(
      find.ancestor(
          of: find.text('Signing...'), matching: find.byType(FilledButton)),
    );
    expect(signButton.onPressed, isNull);
    expect(find.text('Checking...'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile profile groups identity, statistics and library actions',
      (tester) async {
    const size = Size(393, 852);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _loadPreviewFonts(tester);
    await tester.pumpWidget(_profile());
    await _loadProfile(tester);
    await _capture(tester, 'profile-mobile-signed-in');

    expect(
      tester.getRect(find.byType(Avatar)).right,
      lessThan(tester.getRect(find.text(_username)).left),
    );
    expect(
      tester.getRect(find.text('Lv.22')).bottom,
      lessThan(tester.getRect(find.text('EXP')).top),
    );
    final stats = find.byKey(const ValueKey('profile-statistics-row'));
    expect(stats, findsOneWidget);
    expect(
        find.descendant(of: stats, matching: find.text('35%')), findsOneWidget);
    expect(find.descendant(of: stats, matching: find.text('987654321')),
        findsOneWidget);
    expect(
        find.descendant(of: stats, matching: find.text('2')), findsOneWidget);
    final library = find.byKey(const ValueKey('profile-library-card'));
    expect(library, findsOneWidget);

    for (final label in [
      'Favorites',
      'History',
      'Download List',
      'Comments',
    ]) {
      final target = find.text(label);
      expect(target, findsOneWidget, reason: label);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();

      final row = find.ancestor(of: target, matching: find.byType(InkWell));
      expect(row, findsOneWidget, reason: label);
      final rect = tester.getRect(row);
      expect(rect.width, greaterThanOrEqualTo(350), reason: label);
      expect(rect.height, greaterThanOrEqualTo(60), reason: label);
      expect(find.ancestor(of: target, matching: library), findsOneWidget);
      expect(rect.left, greaterThanOrEqualTo(0), reason: label);
      expect(rect.right, lessThanOrEqualTo(size.width), reason: label);
      expect(target.hitTestable(), findsOneWidget, reason: label);
      expect(tester.takeException(), isNull, reason: label);
    }
  });

  testWidgets('wide signed-in profile and library share a bounded row',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_profile(textScale: 1.5));
    await _loadProfile(tester);
    final profilePosition = tester.getTopLeft(find.text(_username));
    final libraryPosition = tester.getTopLeft(find.text('Library'));
    expect(libraryPosition.dx, greaterThan(profilePosition.dx));
    expect((profilePosition.dy - libraryPosition.dy).abs(), lessThan(40));

    final content = find.byWidgetPredicate(
      (widget) =>
          widget is ConstrainedBox && widget.constraints.maxWidth == 1120,
    );
    expect(tester.getSize(content).width, 1120);
    expect(tester.getTopLeft(content).dx, 240);
    expect(find.text('Manual Sign-in').hitTestable(), findsOneWidget);
    expect(find.text('Comments').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'compact signed-in card follows ${dark ? 'dark' : 'light'} theme',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      _selfInfo.addAll({
        'username': 'baigeiyyds',
        'uid': 4444611,
        'fname': '',
        'email': 'reader@example.com',
        'level_name': 'Quiet reader',
        'level': 9,
        'expPercent': 78.0,
        'coin': 24294,
        'badges': <String>[],
        'message': 'Welcome! A long signature wraps without widening the card.',
      });
      dailySignStatus = DailySignStatus.signed;
      await _loadPreviewFonts(tester);
      await tester.pumpWidget(_profile(dark: dark));
      await _loadProfile(tester);
      final card = tester.widget<Container>(
        find.byKey(const ValueKey('profile-account-card')),
      );
      final color = (card.decoration! as BoxDecoration).color;
      final theme = Theme.of(tester.element(find.byType(UserScreen)));
      expect(
          color,
          dark
              ? const Color(0xFF17272E)
              : theme.colorScheme.surfaceContainerLow);
      expect(tester.widget<Text>(find.text('baigeiyyds')).style!.fontSize, 19);
      expect(tester.widget<Text>(find.text('baigeiyyds')).style!.fontWeight,
          FontWeight.w500);
      final sign = find.byKey(const ValueKey('profile-daily-sign'));
      expect(tester.getRect(sign).left,
          greaterThan(tester.getRect(find.text('UID 4444611')).left));
      expect(find.text('Signed in'), findsOneWidget);
      expect(tester.widget<FilledButton>(sign).onPressed, isNull);
      expect(
          tester
              .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator))
              .value,
          .78);
      expect(find.text('78%'), findsOneWidget);
      expect(find.text('24294'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'profile-mobile-${dark ? 'dark' : 'light'}');
    });
  }

  testWidgets('profile sign-in action still updates real daily status',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_profile());
    await _loadProfile(tester);
    await tester.tap(find.byKey(const ValueKey('profile-daily-sign')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(_requests.where((method) => method == 'daily'), hasLength(1));
    expect(dailySignStatus, DailySignStatus.signed);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('profile-daily-sign')),
        matching: find.text('Signed in'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
