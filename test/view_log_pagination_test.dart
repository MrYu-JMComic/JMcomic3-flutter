import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_controller_mode.dart';
import 'package:jmcomic3/configs/pager_cover_rate.dart';
import 'package:jmcomic3/configs/pager_view_mode.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/comic_list.dart';
import 'package:jmcomic3/screens/components/content_error.dart';
import 'package:jmcomic3/screens/view_log_screen.dart';

Future<List<int>> _mountHistory(WidgetTester tester,
    {required List<List<int>> pages,
    PagerControllerMode mode = PagerControllerMode.pager,
    int? failOnceOnPage}) async {
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final requestedPages = <int>[];
  final pendingCover = Completer<String>();
  final properties = {
    'pager_controller_mode': mode.toString(),
    'pager_view_mode': PagerViewMode.cover.toString(),
    'pager_cover_rate': PagerCoverRate.rate3x4.toString(),
    'pager_column_number': '3',
  };
  final total = pages.fold<int>(0, (count, page) => count + page.length);
  messenger.setMockMethodCallHandler(channel, (call) async {
    final request = jsonDecode(call.arguments as String) as Map;
    Object response;
    switch (request['method']) {
      case 'load_property':
        response = properties[request['params']] ?? '';
        break;
      case 'page_view_log':
        final page = int.parse(request['params'].toString());
        requestedPages.add(page);
        if (page == failOnceOnPage &&
            requestedPages.where((requested) => requested == page).length ==
                1) {
          return jsonEncode(
              {'error_message': 'fixture failure', 'response_data': ''});
        }
        final ids = page <= pages.length ? pages[page - 1] : <int>[];
        response = {
          'total': total,
          'page_size': 80,
          'content': [
            for (final id in ids) {'id': id, 'name': 'History $id'}
          ],
        };
        break;
      case 'jm_3x4_cover':
        return pendingCover.future;
      default:
        throw StateError('Unexpected history call: ${request['method']}');
    }
    return jsonEncode({
      'error_message': '',
      'response_data': response is String ? response : jsonEncode(response),
    });
  });
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    messenger.setMockMethodCallHandler(channel, null);
  });
  await initPagerControllerMode();
  await initPagerViewMode();
  await initPagerCoverRate();
  await initPagerColumnCount();
  await tester.pumpWidget(const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates: [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: ViewLogScreen(),
  ));
  await tester.pumpAndSettle();
  return requestedPages;
}

List<int> _batch(int start, int count) =>
    List.generate(count, (i) => start + i);
Iterable<int> _visibleIds(WidgetTester tester) => tester
    .widget<ComicList>(find.byType(ComicList))
    .data
    .map((comic) => comic.id);

void main() {
  testWidgets('local history has exact totals and 80-item pages',
      (tester) async {
    final requests = await _mountHistory(tester,
        pages: [_batch(1, 80), _batch(81, 80), _batch(161, 5)]);
    expect(find.text('Page 1 / 3'), findsOneWidget);
    expect(_visibleIds(tester), _batch(1, 80));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 / 3'), findsOneWidget);
    expect(_visibleIds(tester), _batch(81, 80));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Page 3 / 3'), findsOneWidget);
    expect(_visibleIds(tester), _batch(161, 5));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(requests, [1, 2, 3]);
    await tester.tap(find.text('Prev'));
    await tester.pumpAndSettle();
    expect(_visibleIds(tester), _batch(81, 80));
    expect(requests, [1, 2, 3]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local history retries a failed page without probing past total',
      (tester) async {
    final requests = await _mountHistory(tester,
        pages: [_batch(1, 80), _batch(81, 1)], failOnceOnPage: 2);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.widget<ContentError>(find.byType(ContentError)).onRefresh();
    await tester.pumpAndSettle();
    expect(requests, [1, 2, 2]);
    expect(_visibleIds(tester), [81]);
    expect(find.text('Page 2 / 2'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(requests, [1, 2, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history retains accurate totals after page-cache eviction',
      (tester) async {
    await _mountHistory(tester, pages: [
      for (var page = 0; page < 8; page++) _batch(page * 80 + 1, 80)
    ]);
    for (var page = 2; page <= 8; page++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    for (var page = 7; page >= 1; page--) {
      await tester.tap(find.text('Prev'));
      await tester.pumpAndSettle();
      expect(_visibleIds(tester), _batch((page - 1) * 80 + 1, 80));
      expect(find.text('Page $page / 8'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty local history stays on a single empty page',
      (tester) async {
    final requests = await _mountHistory(tester, pages: []);
    expect(_visibleIds(tester), isEmpty);
    expect(find.text('Page 1 / 1'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(requests, [1]);
  });

  testWidgets('history stream scrolls through local 80-item batches',
      (tester) async {
    final requests = await _mountHistory(tester,
        mode: PagerControllerMode.stream,
        pages: [_batch(1, 80), _batch(81, 80), _batch(161, 5)]);
    expect(find.text('Loaded 80 / 165 items'), findsOneWidget);
    for (var attempt = 0; attempt < 4; attempt++) {
      await tester.drag(find.byType(GridView), const Offset(0, -20000));
      await tester.pumpAndSettle();
    }
    expect(requests, [1, 2, 3]);
    expect(_visibleIds(tester), _batch(1, 165));
    expect(find.text('Loaded 3 / 3 pages'), findsOneWidget);
    expect(find.text('Loaded 165 / 165 items'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
