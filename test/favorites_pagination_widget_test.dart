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
import 'package:jmcomic3/screens/components/comic_list.dart';

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
  required int total,
  int batchSize = 20,
  int? count,
  List<List<int>>? items,
  int? failOnceOnPage,
  Completer<void>? secondPageGate,
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
          'count': 0,
          'list': <dynamic>[],
          'folder_list': <dynamic>[],
        };
        break;
      case 'favorites':
        final params = jsonDecode(payload['params'] as String) as Map;
        final page = params['page'] as int;
        pages.add(page);
        if (page == 2 && secondPageGate != null) await secondPageGate.future;
        if (page == failOnceOnPage &&
            pages.where((requested) => requested == page).length == 1) {
          return jsonEncode(
              {'error_message': 'fixture failure', 'response_data': ''});
        }
        final offset = (page - 1) * batchSize;
        final remaining = total - offset;
        final length = remaining <= 0
            ? 0
            : remaining < batchSize
                ? remaining
                : batchSize;
        final ids = items == null
            ? List.generate(length, (index) => offset + index + 1)
            : page <= items.length
                ? items[page - 1]
                : <int>[];
        response = {
          'total': total,
          // count describes this response, including the short final batch.
          'count': count ?? ids.length,
          'list': ids.map(_comicFixture).toList(),
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
    if (secondPageGate != null && !secondPageGate.isCompleted) {
      secondPageGate.complete();
    }
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
  if (secondPageGate == null) {
    await tester.pumpAndSettle();
  } else {
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump();
    }
  }
  expect(tester.takeException(), isNull);
  return pages;
}

void main() {
  testWidgets(
      'favorites pager keeps first batch capacity on the short final page',
      (tester) async {
    final pages = await _mountFavorites(
      tester,
      mode: PagerControllerMode.pager,
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
      'favorites stream keeps first batch capacity on the short final page',
      (tester) async {
    final pages = await _mountFavorites(
      tester,
      mode: PagerControllerMode.stream,
      total: 87,
    );
    expect(pages, [1]);
    expect(find.text('Loaded 1 / 5 pages'), findsOneWidget);
    for (var attempt = 0; attempt < 7; attempt++) {
      await tester.drag(find.byType(GridView), const Offset(0, -4000));
      await tester.pumpAndSettle();
    }
    expect(pages, [1, 2, 3, 4, 5]);
    expect(tester.widget<ComicList>(find.byType(ComicList)).data.length, 87);
    expect(find.text('Loaded 5 / 5 pages'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorites stream passes sparse pages and deduplicates batches',
      (tester) async {
    final pages = await _mountFavorites(tester,
        mode: PagerControllerMode.stream,
        batchSize: 3,
        total: 13,
        items: [
          [1, 2, 3],
          [],
          [3, 4],
          [4, 5],
          [6],
        ]);
    for (var attempt = 0; attempt < 4; attempt++) {
      await tester.drag(find.byType(GridView), const Offset(0, -2000));
      await tester.pumpAndSettle();
    }
    expect(pages, [1, 2, 3, 4, 5]);
    expect(
        tester.widget<ComicList>(find.byType(ComicList)).data.map((c) => c.id),
        [1, 2, 3, 4, 5, 6]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorites stream stops repeated batches without request loops',
      (tester) async {
    final pages = await _mountFavorites(tester,
        mode: PagerControllerMode.stream,
        batchSize: 3,
        total: 30,
        items: [
          [1, 2, 3],
          [1, 2, 3],
        ]);
    await tester.drag(find.byType(GridView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(pages, [1, 2]);
    expect(tester.widget<ComicList>(find.byType(ComicList)).data.length, 3);
  });

  testWidgets('favorites stream waits for explicit retry after a failed batch',
      (tester) async {
    final pages = await _mountFavorites(tester,
        mode: PagerControllerMode.stream,
        batchSize: 3,
        total: 9,
        failOnceOnPage: 2);
    expect(pages, [1, 2]);
    await tester.drag(find.byType(GridView), const Offset(0, -2000));
    await tester.pump(const Duration(seconds: 1));
    expect(pages, [1, 2]);
    await tester.tap(find.byIcon(Icons.sync_problem_rounded));
    await tester.pumpAndSettle();
    expect(pages, [1, 2, 2, 3]);
    expect(tester.widget<ComicList>(find.byType(ComicList)).data.length, 9);
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorites stream does not duplicate an in-flight page request',
      (tester) async {
    final gate = Completer<void>();
    final pages = await _mountFavorites(tester,
        mode: PagerControllerMode.stream,
        batchSize: 3,
        total: 9,
        secondPageGate: gate);
    expect(pages, [1, 2]);
    for (var attempt = 0; attempt < 3; attempt++) {
      await tester.drag(find.byType(GridView), const Offset(0, -1000));
      await tester.pump();
    }
    expect(pages, [1, 2]);
    gate.complete();
    await tester.pumpAndSettle();
    expect(pages, [1, 2, 3]);
    expect(tester.widget<ComicList>(find.byType(ComicList)).data.length, 9);
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorites stream scrolls through complete batches in order',
      (tester) async {
    final pages = await _mountFavorites(tester,
        mode: PagerControllerMode.stream, total: 47);
    expect(pages, [1]);
    for (var attempt = 0; attempt < 4; attempt++) {
      await tester.drag(find.byType(GridView), const Offset(0, -4000));
      await tester.pumpAndSettle();
    }
    expect(pages, [1, 2, 3]);
    expect(
        tester.widget<ComicList>(find.byType(ComicList)).data.map((c) => c.id),
        List.generate(47, (index) => index + 1));
    expect(find.text('Loaded 47 / 47 items'), findsOneWidget);
    expect(find.text('Loaded 3 / 3 pages'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final total in [21, 47]) {
    testWidgets(
        'favorites pager shows ${total == 21 ? 2 : 3} pages for $total items',
        (tester) async {
      final maxPage = total == 21 ? 2 : 3;
      final pages = await _mountFavorites(tester,
          mode: PagerControllerMode.pager, total: total);
      expect(find.text('Page 1 / $maxPage'), findsOneWidget);
      expect(tester.widget<ComicList>(find.byType(ComicList)).data.length, 20);
      for (var page = 2; page <= maxPage; page++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('Page $page / $maxPage'), findsOneWidget);
      }
      expect(tester.widget<ComicList>(find.byType(ComicList)).data.length,
          total % 20);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(pages, List.generate(maxPage, (index) => index + 1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('favorites stream stops after the one-item second page',
      (tester) async {
    final pages = await _mountFavorites(tester,
        mode: PagerControllerMode.stream, total: 21);
    expect(pages, [1]);
    for (var attempt = 0; attempt < 4; attempt++) {
      await tester.drag(find.byType(GridView), const Offset(0, -4000));
      await tester.pumpAndSettle();
    }
    expect(pages, [1, 2]);
    expect(tester.widget<ComicList>(find.byType(ComicList)).data.length, 21);
    expect(find.text('Loaded 2 / 2 pages'), findsOneWidget);
    expect(find.text('Loaded 21 / 21 items'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final count in [0, -20, 21, 200]) {
    for (final mode in PagerControllerMode.values) {
      testWidgets('favorites $mode ignores misleading API count $count',
          (tester) async {
        final pages =
            await _mountFavorites(tester, mode: mode, count: count, total: 21);
        if (mode == PagerControllerMode.pager) {
          expect(find.text('Page 1 / 2'), findsOneWidget);
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
          expect(find.text('Page 2 / 2'), findsOneWidget);
          await tester.tap(find.text('Next'));
        } else {
          for (var attempt = 0; attempt < 4; attempt++) {
            await tester.drag(find.byType(GridView), const Offset(0, -4000));
            await tester.pumpAndSettle();
          }
          expect(find.text('Loaded 2 / 2 pages'), findsOneWidget);
        }
        await tester.pumpAndSettle();
        expect(pages, [1, 2]);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
