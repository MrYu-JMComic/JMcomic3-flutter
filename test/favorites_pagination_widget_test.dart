import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/login.dart' as login_config;
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_controller_mode.dart';
import 'package:jmcomic3/configs/pager_cover_rate.dart';
import 'package:jmcomic3/configs/pager_view_mode.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/favorites_screen.dart';

Map<String, dynamic> _comicFixture(int id) => {
      'id': id,
      'author': 'author',
      'description': '',
      'name': 'comic $id',
      'image': '$id.jpg',
      'category': {'id': '1', 'title': 'category'},
      'category_sub': {'id': '2', 'title': 'subcategory'},
      'update_at': 0,
      'addtime': 0,
    };

Map<String, dynamic> _selfInfoFixture() => {
      'uid': 1,
      'username': 'test',
      'email': '',
      'emailverified': '',
      'photo': '',
      'fname': '',
      'gender': '',
      'message': '',
      'coin': 0,
      'album_favorites': 0,
      's': 'session',
      'level_name': '',
      'level': 1,
      'nextLevelExp': 0,
      'exp': '0',
      'expPercent': 0.0,
      'badges': <dynamic>[],
      'album_favorites_max': 0,
    };

Future<List<int>> _mountFavorites(
  WidgetTester tester, {
  required PagerControllerMode mode,
  required int count,
  required int total,
}) async {
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final pages = <int>[];
  final pendingCover = Completer<String>();
  final properties = <String, String>{
    'pager_controller_mode': mode.toString(),
    'pager_view_mode': PagerViewMode.cover.toString(),
    'pager_cover_rate': PagerCoverRate.rate3x4.toString(),
    'pager_column_number': '4',
  };

  messenger.setMockMethodCallHandler(channel, (call) async {
    final payload = jsonDecode(call.arguments as String) as Map;
    final method = payload['method'];
    Object response = '';
    switch (method) {
      case 'load_property':
        response = properties[payload['params']] ?? '';
        break;
      case 'login':
        response = _selfInfoFixture();
        break;
      case 'favorite':
        response = {
          'total': 0,
          'count': 20,
          'list': <dynamic>[],
          'folder_list': <dynamic>[],
        };
        break;
      case 'favorites':
        final params = jsonDecode(payload['params'] as String) as Map;
        final page = params['page'] as int;
        pages.add(page);
        response = {
          'total': total,
          'count': count,
          // 故意只返回三条，验证总页数来自接口容量而不是实际列表长度。
          'list':
              List.generate(3, (index) => _comicFixture(page * 100 + index)),
          'folder_list': <dynamic>[],
        };
        break;
      case 'jm_3x4_cover':
        // 分页组件测试保留封面加载状态，避免引入真实文件或网络请求。
        return pendingCover.future;
    }
    return jsonEncode({
      'error_message': '',
      'response_data': response is String ? response : jsonEncode(response),
    });
  });
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    messenger.setMockMethodCallHandler(channel, null);
    login_config.favData = [];
  });

  await initPagerControllerMode();
  await initPagerViewMode();
  await initPagerCoverRate();
  await initPagerColumnCount();
  await tester.pumpWidget(const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(key: ValueKey('login_context'))),
  ));
  await login_config.login(
    'test',
    'password',
    tester.element(find.byKey(const ValueKey('login_context'))),
  );
  await tester.pumpWidget(const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: FavoritesScreen(),
  ));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return pages;
}

void main() {
  testWidgets(
      'favorites pager uses count and stops at the calculated last page',
      (tester) async {
    final pages = await _mountFavorites(
      tester,
      mode: PagerControllerMode.pager,
      count: 20,
      total: 87,
    );
    expect(find.text('Page 1 / 5'), findsOneWidget);
    expect(pages, [1]);

    for (var page = 2; page <= 5; page++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Page $page / 5'), findsOneWidget);
    }
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(pages, [1, 2, 3, 4, 5]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'favorites stream uses API capacity instead of returned item count',
      (tester) async {
    await _mountFavorites(
      tester,
      mode: PagerControllerMode.stream,
      count: 20,
      total: 87,
    );
    expect(find.text('Loaded 1 / 5 pages'), findsOneWidget);
    expect(find.text('Loaded 3 / 87 items'), findsOneWidget);
  });

  for (final count in [0, -20]) {
    for (final mode in PagerControllerMode.values) {
      testWidgets('favorites $mode falls back when API count is $count',
          (tester) async {
        await _mountFavorites(tester, mode: mode, count: count, total: 9);
        // 无效容量回退为实际三条，保留后续两页的访问能力。
        final label = mode == PagerControllerMode.pager
            ? 'Page 1 / 3'
            : 'Loaded 1 / 3 pages';
        expect(find.text(label), findsOneWidget);
      });
    }
  }
}
