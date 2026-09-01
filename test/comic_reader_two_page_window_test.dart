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
import 'package:jmcomic3/configs/reader_feature_flags.dart';
import 'package:jmcomic3/configs/two_page_direction.dart';
import 'package:jmcomic3/configs/volume_key_control.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/comic_reader_screen.dart';
import 'package:photo_view/photo_view_gallery.dart';

const _methodsChannel = MethodChannel('methods');

ChapterResponse _chapter(List<String> images) => ChapterResponse(
      id: 10,
      series: [Series(id: 10, name: 'Chapter', sort: '1')],
      tags: '',
      name: 'Chapter',
      images: images,
      seriesId: 10,
      isFavorite: false,
      liked: false,
    );

ComicBasic _comic() => ComicBasic(
      id: 1,
      author: 'author',
      description: '',
      name: 'Test comic',
      image: '',
    );

Future<void> _initConfig() async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_methodsChannel, (call) async {
    if (call.method != 'invoke') {
      return null;
    }
    final request = jsonDecode(call.arguments as String) as Map;
    final method = request['method'];
    if (method == 'load_property') {
      final key = request['params'];
      const values = <String, String>{
        'readerType': 'ReaderType.twoPageGallery',
        'readerDirection': 'ReaderDirection.rightToLeft',
        'twoPageDirection': 'TwoPageDirection.rightToLeft',
        'reader_controller_type': 'ReaderControllerType.controller',
        'reader_slider_position': 'ReaderSliderPosition.bottom',
        'volumeKeyControl': 'false',
        'noAnimation': 'false',
        'ignoreVewLog': 'false',
      };
      return jsonEncode({
        'error_message': '',
        'response_data': values[key] ?? '',
      });
    }
    if (method == 'jm_page_image') {
      return jsonEncode({
        'error_message': '',
        'response_data': 'images/ic.png',
      });
    }
    if (method == 'image_size') {
      return jsonEncode({
        'error_message': '',
        'response_data': jsonEncode({'w': 1, 'h': 1}),
      });
    }
    return jsonEncode({'error_message': '', 'response_data': ''});
  });
  await initReaderType();
  await initReaderDirection();
  await initTwoPageDirection();
  await initReaderControllerType();
  await initReaderSliderPosition();
  await initVolumeKeyControl();
  await initNoAnimation();
  await initIgnoreVewLog();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_initConfig);
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_methodsChannel, null);
  });

  testWidgets('windowed two-page gallery builds bounded cover/RTL slots',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ComicReaderScreen(
          comic: _comic(),
          series: const [],
          chapterId: 10,
          initRank: 2,
          loadChapter: (_) async => _chapter(
            List<String>.filled(5, 'images/ic.png', growable: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gallery = tester.widget<PhotoViewGallery>(
      find.byType(PhotoViewGallery),
    );
    if (!readerTwoPageWindowV1) {
      // The default build intentionally keeps the legacy static gallery.
      expect(gallery.itemCount, isNull);
      expect(gallery.pageOptions, hasLength(3));
      expect(tester.takeException(), isNull);
      return;
    }
    expect(gallery.itemCount, 3);
    expect(gallery.reverse, isTrue);
    expect(gallery.pageController?.initialPage, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('windowed two-page gallery handles a one-page chapter',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ComicReaderScreen(
          comic: _comic(),
          series: const [],
          chapterId: 10,
          initRank: 99,
          loadChapter: (_) async => _chapter(const ['images/ic.png']),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gallery = tester.widget<PhotoViewGallery>(
      find.byType(PhotoViewGallery),
    );
    if (!readerTwoPageWindowV1) {
      expect(gallery.itemCount, isNull);
      expect(gallery.pageOptions, hasLength(1));
      expect(tester.takeException(), isNull);
      return;
    }
    expect(gallery.itemCount, 1);
    expect(gallery.pageController?.initialPage, 0);
    expect(tester.takeException(), isNull);
  });
}
