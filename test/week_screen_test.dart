import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_controller_mode.dart';
import 'package:jmcomic3/configs/pager_cover_rate.dart';
import 'package:jmcomic3/configs/pager_view_mode.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/content_builder.dart';
import 'package:jmcomic3/screens/week_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('weekly refresh and issue switch send current API parameters',
      (tester) async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final requests = <Map<String, dynamic>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final payload = jsonDecode(call.arguments as String);
      if (payload['method'] == 'load_property') {
        return jsonEncode({
          'error_message': '',
          'response_data': payload['params'] == 'pager_controller_mode'
              ? 'PagerControllerMode.pager'
              : '',
        });
      }
      if (payload['method'] == 'week_filter') {
        requests.add(
            Map<String, dynamic>.from(jsonDecode(payload['params'] as String)));
        return jsonEncode({
          'error_message': '',
          'response_data': jsonEncode({'list': <Object>[], 'total': 0}),
        });
      }
      throw StateError('Unexpected method: ${payload['method']}');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await initPagerControllerMode();
    await initPagerViewMode();
    await initPagerCoverRate();
    await initPagerColumnCount();
    final categoryNotifier = ValueNotifier<String?>('issue-1');
    addTearDown(categoryNotifier.dispose);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Scaffold(
        body: WeekContent(
          data: WeekData.fromJson({
            'categories': [
              {'id': 'issue-1', 'time': '2026-10-07', 'title': 'Issue 1'},
              {'id': 'issue-2', 'time': '2026-09-30', 'title': 'Issue 2'},
            ],
            'type': [
              {'id': 'hot', 'title': 'Hot'},
            ],
          }),
          initialCategoryId: 'issue-1',
          categoryNotifier: categoryNotifier,
          onCategoryChanged: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(requests, [
      {'category_id': 'issue-1', 'type_id': 'hot', 'page': 1},
    ]);

    // 调用分页器实际的刷新入口，回归“内层已刷新但每周必看仍命中旧缓存”的问题。
    final builder = tester.widget<ContentBuilder<dynamic>>(
        find.byWidgetPredicate((widget) => widget is ContentBuilder));
    await builder.onRefresh();
    await tester.pumpAndSettle();
    expect(requests, [
      {'category_id': 'issue-1', 'type_id': 'hot', 'page': 1},
      {'category_id': 'issue-1', 'type_id': 'hot', 'page': 1},
    ]);
    categoryNotifier.value = 'issue-2';
    await tester.pumpAndSettle();
    expect(
        requests.last, {'category_id': 'issue-2', 'type_id': 'hot', 'page': 1});
    expect(requests, hasLength(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
