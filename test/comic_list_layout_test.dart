import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_cover_rate.dart';
import 'package:jmcomic3/configs/pager_view_mode.dart';
import 'package:jmcomic3/screens/components/comic_info_card.dart';
import 'package:jmcomic3/screens/components/comic_list.dart';
import 'package:jmcomic3/screens/components/images.dart';
import 'package:jmcomic3/screens/components/types.dart';

const _channel = MethodChannel('methods');

ComicSimple _comic(int id) => ComicSimple(
      id: id,
      author: 'A long author name that can wrap safely',
      description: '',
      name: 'Comic $id: a long title that should occupy two readable lines',
      image: '',
      category: ComicSimpleCategory(title: 'A long primary category'),
      categorySub: ComicSimpleCategory(title: 'A long secondary category'),
      addtime: 1735689600,
      updateAt: 1735776000,
    );

Future<void> _initPreferences(
  PagerViewMode mode,
  PagerCoverRate ratio, {
  int columns = 3,
}) async {
  final pendingCover = Completer<String>();
  final properties = {
    'pager_view_mode': mode.toString(),
    'pager_cover_rate': ratio.toString(),
    'pager_column_number': '$columns',
  };
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_channel, (call) async {
    final request = jsonDecode(call.arguments as String) as Map;
    if (request['method'] == 'jm_3x4_cover' ||
        request['method'] == 'jm_square_cover') {
      return pendingCover.future;
    }
    return jsonEncode({
      'error_message': '',
      'response_data': properties[request['params']] ?? '',
    });
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  await initPagerViewMode();
  await initPagerCoverRate();
  await initPagerColumnCount();
}

Widget _host(Widget child, {double width = 420, double textScale = 1}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: MediaQuery(
            data: MediaQueryData(
              size: const Size(1000, 800),
              textScaler: TextScaler.linear(textScale),
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final mode in [
    PagerViewMode.cover,
    PagerViewMode.titleInCover,
    PagerViewMode.titleAndCover,
  ]) {
    for (final ratio in PagerCoverRate.values) {
      testWidgets('$mode $ratio fits its parent and preserves selected columns',
          (tester) async {
        await _initPreferences(mode, ratio);
        await tester.pumpWidget(_host(
          SingleChildScrollView(
            child: ComicList(
              data: List.generate(4, _comic),
              inScroll: true,
              appendList: const [SizedBox(key: ValueKey('appended'))],
            ),
          ),
          textScale: 2,
        ));
        await tester.pump();

        final covers = find.byType(
            ratio == PagerCoverRate.rate3x4 ? JM3x4Cover : JMSquareCover);
        final first = tester.getRect(covers.at(0));
        final second = tester.getRect(covers.at(1));
        final third = tester.getRect(covers.at(2));
        final fourth = tester.getRect(covers.at(3));
        expect(first.left, 12);
        expect(first.width, closeTo(124, .001));
        expect(first.width / first.height,
            closeTo(ratio == PagerCoverRate.rate3x4 ? .75 : 1, .001));
        expect(second.left - first.right, closeTo(12, .001));
        expect(third.top, first.top);
        expect(third.right, closeTo(408, .001));
        expect(fourth.left, first.left);
        expect(fourth.top, greaterThan(first.bottom));
        expect(find.byKey(const ValueKey('appended')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'title captions scale while scroll callbacks and appended items work',
      (tester) async {
    await _initPreferences(
      PagerViewMode.titleAndCover,
      PagerCoverRate.rate3x4,
      columns: 4,
    );
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var scrollEvents = 0;
    await tester.pumpWidget(_host(
      ComicList(
        data: List.generate(40, (index) => _comic(index + 100)),
        controller: controller,
        onScroll: () => scrollEvents++,
        appendList: const [SizedBox(key: ValueKey('appended'))],
      ),
      width: 320,
      textScale: 2,
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(JM3x4Cover).evaluate().length, lessThan(40));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(scrollEvents, greaterThan(0));
    expect(find.byKey(const ValueKey('appended')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('info metadata wraps at a narrow width with large text',
      (tester) async {
    await _initPreferences(PagerViewMode.info, PagerCoverRate.rate3x4);
    await tester.pumpWidget(_host(
      SingleChildScrollView(child: ComicInfoCard(_comic(200))),
      width: 320,
      textScale: 2,
    ));
    await tester.pump();

    final primary = tester.getRect(find.text('A long primary category'));
    final secondary = tester.getRect(find.text('A long secondary category'));
    final published = tester.getRect(find.textContaining('发布:'));
    final updated = tester.getRect(find.textContaining('更新:'));
    expect(secondary.top, greaterThan(primary.bottom));
    expect(updated.top, greaterThan(published.bottom));
    expect(secondary.right, lessThanOrEqualTo(308));
    expect(updated.right, lessThanOrEqualTo(308));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ten configured columns remain valid in a tiny parent',
      (tester) async {
    await _initPreferences(
      PagerViewMode.titleAndCover,
      PagerCoverRate.rate3x4,
      columns: 10,
    );
    await tester.pumpWidget(_host(
      SingleChildScrollView(
        child: ComicList(
          data: List.generate(10, (index) => _comic(index + 300)),
          inScroll: true,
        ),
      ),
      width: 128,
      textScale: 2,
    ));
    await tester.pump();
    final covers = find.byType(JM3x4Cover);
    expect(covers, findsNWidgets(10));
    final first = tester.getRect(covers.first);
    final last = tester.getRect(covers.last);
    expect(first.width, greaterThan(0));
    expect(last.top, first.top);
    expect(last.right, lessThanOrEqualTo(128));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long pressing a caption keeps its comic action attached',
      (tester) async {
    await _initPreferences(
      PagerViewMode.titleAndCover,
      PagerCoverRate.rateSquare,
      columns: 2,
    );
    final comic = _comic(400);
    ComicBasic? selected;
    await tester.pumpWidget(_host(ComicList(
      data: [comic],
      longPressMenuItems: [
        ComicLongPressMenuItem('Favorite', (value) => selected = value),
      ],
    )));
    await tester.pump();
    await tester.longPress(find.text(comic.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorite'));
    await tester.pumpAndSettle();
    expect(selected, same(comic));
    expect(tester.takeException(), isNull);
  });
}
