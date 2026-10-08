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
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return jsonEncode(
              {'error_message': 'fixture failure', 'response_data': ''});
        }
        final ids = page <= pages.length ? pages[page - 1] : <int>[];
        response = {
          // Reproduce a backend response that only reports this batch's size.
          'total': ids.length,
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
  testWidgets('history can retry a failed next page without treating it as end',
      (tester) async {
    final requests = await _mountHistory(tester,
        pages: [_batch(1, 20), _batch(21, 20)], failOnceOnPage: 2);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pumpAndSettle();
    final error = tester.widget<ContentError>(find.byType(ContentError));
    await error.onRefresh();
    await tester.pumpAndSettle();
    expect(requests, [1, 2, 2]);
    expect(_visibleIds(tester), _batch(21, 20));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'history keeps discovered pages after the first page leaves cache',
      (tester) async {
    await _mountHistory(tester,
        pages: [for (var page = 0; page < 8; page++) _batch(page * 2 + 1, 2)]);
    for (var page = 2; page <= 8; page++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Page 8 / 8'), findsOneWidget);
    for (var page = 7; page >= 1; page--) {
      await tester.tap(find.text('Prev'));
      await tester.pumpAndSettle();
      expect(_visibleIds(tester), _batch((page - 1) * 2 + 1, 2));
    }
    expect(find.text('Page 1 / 8'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 / 8'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history pager loads past 20 and retains the last nonempty page',
      (tester) async {
    final requests = await _mountHistory(tester,
        pages: [_batch(1, 20), _batch(21, 20), _batch(41, 5)]);
    expect(_visibleIds(tester), _batch(1, 20));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(requests, [1, 2]);
    expect(_visibleIds(tester), _batch(21, 20));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(_visibleIds(tester), _batch(41, 5));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(requests, [1, 2, 3, 4]);
    expect(_visibleIds(tester), _batch(41, 5));
    expect(find.text('Page 3 / 3'), findsOneWidget);
    await tester.tap(find.text('Prev'));
    await tester.pumpAndSettle();
    expect(_visibleIds(tester), _batch(21, 20));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(requests, [1, 2, 3, 4]);
    expect(tester.takeException(), isNull);
  });

  for (final repeat in [false, true]) {
    testWidgets('history stops at ${repeat ? 'repeated' : 'empty'} next page',
        (tester) async {
      final requests = await _mountHistory(tester,
          pages: [_batch(1, 20), if (repeat) _batch(1, 20)]);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(requests, [1, 2]);
      expect(_visibleIds(tester), _batch(1, 20));
      expect(find.text('Page 1 / 1'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(requests, [1, 2]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty history stays on an empty first page', (tester) async {
    final requests = await _mountHistory(tester, pages: []);
    expect(_visibleIds(tester), isEmpty);
    expect(find.text('Page 1 / 1'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(requests, [1]);
  });

  testWidgets('history stream continues beyond a reported one-page total',
      (tester) async {
    final requests = await _mountHistory(tester,
        mode: PagerControllerMode.stream,
        pages: [_batch(1, 20), _batch(21, 20), _batch(41, 5)]);
    for (var attempt = 0; attempt < 8; attempt++) {
      final controller =
          tester.widget<GridView>(find.byType(GridView)).controller!;
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    expect(requests, [1, 2, 3, 4]);
    expect(_visibleIds(tester), _batch(1, 45));
    expect(tester.takeException(), isNull);
  });
}
