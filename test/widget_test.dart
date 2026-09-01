import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/configs/ignore_view_log.dart';
import 'package:jmcomic3/configs/no_animation.dart';
import 'package:jmcomic3/configs/reader_controller_type.dart';
import 'package:jmcomic3/configs/reader_direction.dart';
import 'package:jmcomic3/configs/reader_slider_position.dart';
import 'package:jmcomic3/configs/reader_type.dart';
import 'package:jmcomic3/configs/two_page_direction.dart';
import 'package:jmcomic3/configs/volume_key_control.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/comic_reader_screen.dart';

const _methodsChannel = MethodChannel('methods');

Future<void> _initReaderConfigForTest() async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_methodsChannel, (call) async {
    if (call.method != 'invoke') {
      return null;
    }
    final request =
        jsonDecode(call.arguments as String) as Map<String, dynamic>;
    final method = request['method'];
    var responseData = '';
    if (method == 'jm_page_image') {
      responseData = 'images/ic.png';
    } else if (method == 'image_size') {
      responseData = jsonEncode({'w': 1, 'h': 1});
    }
    return jsonEncode({
      'error_message': '',
      'response_data': responseData,
    });
  });

  // These preferences are normally loaded by InitScreen before a reader is
  // reachable. Widget tests mount the reader directly, so initialize the same
  // defaults through the public config loaders instead of mutating internals.
  await initReaderType();
  await initReaderDirection();
  await initReaderControllerType();
  await initReaderSliderPosition();
  await initTwoPageDirection();
  await initVolumeKeyControl();
  await initNoAnimation();
  await initIgnoreVewLog();
}

ComicBasic _comic() => ComicBasic(
      id: 1,
      author: 'author',
      description: '',
      name: 'Test comic',
      image: '',
    );

ChapterResponse _chapter({List<String> images = const []}) => ChapterResponse(
      id: 10,
      series: [Series(id: 10, name: 'Chapter', sort: '1')],
      tags: '',
      name: 'Chapter',
      images: images,
      seriesId: 10,
      isFavorite: false,
      liked: false,
    );

Widget _reader(Future<ChapterResponse> Function(int) loader,
    {int initRank = 0}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: ComicReaderScreen(
      comic: _comic(),
      series: const [],
      chapterId: 10,
      initRank: initRank,
      loadChapter: loader,
    ),
  );
}

void main() {
  setUpAll(_initReaderConfigForTest);
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_methodsChannel, null);
  });

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

  testWidgets('empty chapter renders a retry placeholder', (tester) async {
    await tester.pumpWidget(_reader((_) async => _chapter()));
    await tester.pumpAndSettle();

    expect(find.text('No content available'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('chapter loader errors render content error state',
      (tester) async {
    await tester.pumpWidget(_reader((_) async => throw StateError('offline')));
    await tester.pumpAndSettle();

    expect(find.byType(ComicReaderScreen), findsOneWidget);
    expect(find.textContaining('offline'), findsOneWidget);
  });

  testWidgets('initial rank outside chapter bounds does not crash reader',
      (tester) async {
    await tester.pumpWidget(_reader(
        (_) async =>
            _chapter(images: const ['https://example.invalid/page.jpg']),
        initRank: 99));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });

  testWidgets('reused reader state resets chapter generation safely',
      (tester) async {
    final loaded = <int>[];
    Future<ChapterResponse> loader(int id) async {
      loaded.add(id);
      return ChapterResponse(
        id: id,
        series: [Series(id: id, name: 'Chapter $id', sort: '$id')],
        tags: '',
        name: 'Chapter $id',
        images: const ['images/ic.png'],
        seriesId: id,
        isFavorite: false,
        liked: false,
      );
    }

    Widget buildReader(int chapterId) {
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ComicReaderScreen(
          key: const ValueKey('same-reader-state'),
          comic: _comic(),
          series: const [],
          chapterId: chapterId,
          initRank: 0,
          loadChapter: loader,
        ),
      );
    }

    await tester.pumpWidget(buildReader(10));
    await tester.pumpAndSettle();
    await tester.pumpWidget(buildReader(11));
    await tester.pumpAndSettle();

    expect(loaded, [10, 11]);
    expect(tester.takeException(), isNull);
  });
}
