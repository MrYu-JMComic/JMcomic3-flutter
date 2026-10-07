import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:another_xlider/another_xlider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/no_animation.dart';
import 'package:jmcomic3/configs/reader_controller_type.dart';
import 'package:jmcomic3/configs/reader_direction.dart';
import 'package:jmcomic3/configs/reader_slider_position.dart';
import 'package:jmcomic3/configs/reader_type.dart';
import 'package:jmcomic3/configs/two_page_direction.dart';
import 'package:jmcomic3/configs/volume_key_control.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/comic_reader_screen.dart';
import 'package:jmcomic3/screens/components/images.dart';
import 'package:jmcomic3/screens/components/reader_preloader.dart';
import 'package:jmcomic3/screens/components/reader_progress.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preload follows order, deduplicates and stops a replaced queue',
      () async {
    final preloader = ReaderPreloader();
    final pending = Completer<void>();
    final loaded = <int>[];
    final released = <int>[];
    final old = preloader.preload(
      indexes: [0, 1, 1, 2],
      load: (index) async {
        loaded.add(index);
        await pending.future;
      },
      releaseStale: released.add,
    );
    final current = preloader.preload(
      indexes: [4, 5, 5, 3],
      load: (index) async => loaded.add(index),
      releaseStale: released.add,
    );
    await current;
    pending.complete();
    await old;
    expect(loaded, [0, 4, 5, 3]);
    expect(released, [0]);
  });

  test('dispose releases a late completion and does not start remaining pages',
      () async {
    final preloader = ReaderPreloader();
    final pending = Completer<void>();
    final loaded = <int>[];
    final released = <int>[];
    final task = preloader.preload(
      indexes: [2, 3, 4],
      load: (index) async {
        loaded.add(index);
        await pending.future;
      },
      releaseStale: released.add,
    );
    preloader.dispose();
    pending.complete();
    await task;
    await preloader.preload(
        indexes: [6],
        load: (index) async => loaded.add(index),
        releaseStale: released.add);
    expect(loaded, [2]);
    expect(released, [2]);
  });

  test('long image covering the viewport center remains the current page', () {
    expect(
        readerPageAtViewportCenter(const [
          ReaderPageBounds(2, -4, 0.8),
          ReaderPageBounds(3, 0.8, 1.05),
          ReaderPageBounds(4, 1.05, 1.4),
        ]),
        2);
    expect(
        readerPageAtViewportCenter(const [
          ReaderPageBounds(2, -4, 0.2),
          ReaderPageBounds(3, 0.2, 0.9),
        ]),
        3);
  });

  late Directory directory;
  final heights = <int>[64, 384, 128, 512, 96, 320, 64, 384, 64, 128];
  final paths = <String>[];
  final viewLogs = <int>[];
  final imageRequests = <String>[];
  Completer<void>? imageGate;
  var direction = ReaderDirection.leftToRight;
  var controlMode = ReaderControllerType.controller;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('jm_reader_regression_');
    for (var index = 0; index < heights.length; index++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(Rect.fromLTWH(0, 0, 64, heights[index].toDouble()),
          Paint()..color = Colors.green);
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, heights[index]);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final path = '${directory.path}/page_$index.png';
      await File(path).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
      paths.add(path);
    }
  });
  tearDownAll(() async => directory.delete(recursive: true));

  setUp(() {
    clearAllImageMemoryCaches();
    imageCache.clear();
    imageCache.clearLiveImages();
    viewLogs.clear();
    imageRequests.clear();
    imageGate = null;
    controlMode = ReaderControllerType.controller;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('methods'),
      (call) async {
        final payload =
            jsonDecode(call.arguments as String) as Map<String, dynamic>;
        final name = payload['method'];
        final params = payload['params'] as String;
        var response = '';
        if (name == 'load_property') {
          response = switch (params) {
            'reader_controller_type' => controlMode.toString(),
            'readerDirection' => direction.toString(),
            'reader_slider_position' => 'ReaderSliderPosition.bottom',
            _ => '',
          };
        } else if (name == 'jm_page_image') {
          final imageName = (jsonDecode(params)
              as Map<String, dynamic>)['image_name'] as String;
          imageRequests.add(imageName);
          if (imageName == '0.png' && imageGate != null) {
            await imageGate!.future;
          }
          response = paths[int.parse(imageName.split('.').first)];
        } else if (name == 'image_size') {
          final index = paths.indexOf(params);
          response = jsonEncode({'w': 64, 'h': heights[index]});
        } else if (name == 'update_view_log') {
          viewLogs.add((jsonDecode(params)
              as Map<String, dynamic>)['last_view_page'] as int);
        } else {
          throw StateError('Unexpected reader method: $name');
        }
        return jsonEncode({'error_message': '', 'response_data': response});
      },
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('methods'), null);
  });

  Future<GlobalKey> mountReader(WidgetTester tester, ReaderType type,
      ReaderDirection readDirection) async {
    direction = readDirection;
    await initReaderControllerType();
    await initReaderDirection();
    await initReaderSliderPosition();
    await initNoAnimation();
    await initVolumeKeyControl();
    await initTwoPageDirection();
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Scaffold(
          body: buildComicReaderForTest(
        key: key,
        chapter: ChapterResponse(
            id: 81234,
            series: [],
            tags: '',
            name: 'Reader regression',
            images: List.generate(heights.length, (index) => '$index.png'),
            seriesId: 81234,
            isFavorite: false,
            liked: false),
        readerType: type,
        direction: readDirection,
      )),
    ));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();
    return key;
  }

  Future<void> doubleTap(WidgetTester tester, Offset point) async {
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(point);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'horizontal free zoom double tap permits single finger pan and restores page swipe',
      (tester) async {
    final key = await mountReader(
        tester, ReaderType.webToonFreeZoom, ReaderDirection.leftToRight);
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer).first);
    final controller = viewer.transformationController!;
    await doubleTap(tester, const Offset(350, 260));
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.9));
    final before = controller.value.storage[12];
    await tester.dragFrom(const Offset(350, 260), const Offset(100, 0));
    await tester.pumpAndSettle();
    final delta = controller.value.storage[12] - before;
    expect(delta.abs(), greaterThan(10));
    expect(delta.abs(), lessThan(180));
    expect(comicReaderProgressForTest(key).current, 0);
    await doubleTap(tester, const Offset(350, 260));
    await tester.dragFrom(const Offset(600, 260), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(comicReaderProgressForTest(key).current, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
      'vertical free zoom double tap routes single finger pan and restores reading scroll',
      (tester) async {
    final key = await mountReader(
        tester, ReaderType.webToonFreeZoom, ReaderDirection.topToBottom);
    await doubleTap(tester, const Offset(350, 260));
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final controller = viewer.transformationController!;
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.9));
    expect(viewer.panEnabled, isTrue);
    final before = controller.value.storage[12];
    await tester.dragFrom(const Offset(350, 260), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect((controller.value.storage[12] - before).abs(), greaterThan(10));
    expect(comicReaderProgressForTest(key).current, 0);
    await doubleTap(tester, const Offset(350, 260));
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.001));
    expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .panEnabled,
        isFalse);
    await tester.dragFrom(const Offset(350, 450), const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(comicReaderProgressForTest(key).current, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('vertical free zoom keeps horizontal pan after pinch handoff',
      (tester) async {
    final key = await mountReader(
        tester, ReaderType.webToonFreeZoom, ReaderDirection.topToBottom);
    final viewerFinder = find.byType(InteractiveViewer);
    final rect = tester.getRect(viewerFinder);
    final viewer = tester.widget<InteractiveViewer>(viewerFinder);
    final controller = viewer.transformationController!;
    final first = await tester.createGesture(
      kind: PointerDeviceKind.touch,
      pointer: 1,
    );
    final second = await tester.createGesture(
      kind: PointerDeviceKind.touch,
      pointer: 2,
    );
    await first.down(Offset(rect.center.dx - 80, rect.center.dy));
    await second.down(Offset(rect.center.dx + 80, rect.center.dy));
    await tester.pump();
    await first.moveTo(Offset(rect.center.dx - 150, rect.center.dy));
    await second.moveTo(Offset(rect.center.dx + 150, rect.center.dy));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.1));

    await second.up();
    await tester.pump();
    expect(tester.widget<InteractiveViewer>(viewerFinder).panEnabled, isFalse);
    final before = controller.value.storage[12];
    await first.moveBy(const Offset(-100, 0));
    await tester.pumpAndSettle();
    await first.up();
    final delta = (controller.value.storage[12] - before).abs();
    expect(delta, greaterThan(10));
    expect(delta, lessThan(180));
    expect(comicReaderProgressForTest(key).current, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  for (final mode in [
    ReaderControllerType.touchDouble,
    ReaderControllerType.touchDoubleOnceNext
  ]) {
    testWidgets('vertical free zoom preserves $mode fullscreen double tap',
        (tester) async {
      controlMode = mode;
      await mountReader(
          tester, ReaderType.webToonFreeZoom, ReaderDirection.topToBottom);
      expect(find.byType(AppBar), findsOneWidget);
      await doubleTap(tester, const Offset(350, 260));
      expect(find.byType(AppBar), findsNothing);
      final viewer =
          tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(viewer.transformationController!.value.getMaxScaleOnAxis(),
          closeTo(1, 0.001));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  for (final type in [
    ReaderType.gallery,
    ReaderType.webToonFreeZoom,
    ReaderType.twoPageGallery
  ]) {
    testWidgets(
        '$type locks slider through intermediate pages and superseded jumps',
        (tester) async {
      final key = await mountReader(tester, type, ReaderDirection.leftToRight);
      jumpComicReaderForTest(key, 8);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(comicReaderProgressForTest(key).slider, 8);
      expect(
          tester
              .widget<FlutterSlider>(find.byType(FlutterSlider))
              .values
              .single,
          8);
      jumpComicReaderForTest(key, 4);
      await tester.pump();
      for (var tick = 0; tick < 3; tick++) {
        await tester.pump(const Duration(milliseconds: 90));
        expect(comicReaderProgressForTest(key).slider, 4);
      }
      await tester.pumpAndSettle();
      expect(comicReaderProgressForTest(key),
          (current: 4, slider: 4, jumpTarget: null));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  for (final type in [ReaderType.webtoon, ReaderType.webToonFreeZoom]) {
    testWidgets('$type jumps to distant varying-height pages by exact index',
        (tester) async {
      final key = await mountReader(tester, type, ReaderDirection.topToBottom);
      jumpComicReaderForTest(key, 7, animation: false);
      await tester.pumpAndSettle();
      expect(comicReaderProgressForTest(key),
          (current: 7, slider: 7, jumpTarget: null));
      jumpComicReaderForTest(key, 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(comicReaderProgressForTest(key).slider, 2);
      await tester.pumpAndSettle();
      expect(comicReaderProgressForTest(key).current, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('exit during an animated jump persists the actual visible page',
      (tester) async {
    final key = await mountReader(
        tester, ReaderType.gallery, ReaderDirection.leftToRight);
    jumpComicReaderForTest(key, 8);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final actual = comicReaderProgressForTest(key).current;
    expect(actual, lessThan(8));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(viewLogs.last, actual);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'two-page controls advance and rewind complete spreads at boundaries',
      (tester) async {
    final key = await mountReader(
        tester, ReaderType.twoPageGallery, ReaderDirection.leftToRight);
    controlComicReaderForTest('DOWN');
    await tester.pumpAndSettle();
    expect(comicReaderProgressForTest(key).current, 2);
    controlComicReaderForTest('UP');
    await tester.pumpAndSettle();
    expect(comicReaderProgressForTest(key).current, 0);
    controlComicReaderForTest('UP');
    await tester.pumpAndSettle();
    expect(comicReaderProgressForTest(key).current, 0);
    for (var index = 0; index < 6; index++) {
      controlComicReaderForTest('DOWN');
      await tester.pumpAndSettle();
    }
    expect(comicReaderProgressForTest(key).current, 8);
    expect(comicReaderProgressForTest(key).slider, 8);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('two-page rapid controls retain the newest spread target',
      (tester) async {
    final key = await mountReader(
        tester, ReaderType.twoPageGallery, ReaderDirection.leftToRight);
    controlComicReaderForTest('DOWN');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    controlComicReaderForTest('DOWN');
    await tester.pump();
    expect(comicReaderProgressForTest(key).slider, 4);
    await tester.pump(const Duration(milliseconds: 90));
    expect(comicReaderProgressForTest(key).slider, 4);
    controlComicReaderForTest('UP');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    controlComicReaderForTest('UP');
    await tester.pumpAndSettle();
    expect(comicReaderProgressForTest(key),
        (current: 0, slider: 0, jumpTarget: null));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
      'late real image completion after reader disposal is evicted and queue stops',
      (tester) async {
    imageGate = Completer<void>();
    await mountReader(tester, ReaderType.gallery, ReaderDirection.leftToRight);
    expect(imageRequests, ['0.png']);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      imageGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    // 实际文件读取与解码跨越 FakeAsync 和引擎任务，交替推进真实 I/O 与帧末监听器清理。
    for (var frame = 0; frame < 20; frame++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    final status = imageCache.statusForKey(PageImageProvider(81234, '0.png'));
    expect(status.keepAlive, isFalse);
    expect(status.pending, isFalse);
    expect(imageRequests, ['0.png']);
    expect(tester.takeException(), isNull);
  });
}
