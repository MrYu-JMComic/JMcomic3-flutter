import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:another_xlider/another_xlider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/no_animation.dart';
import 'package:jmcomic3/configs/reader_controller_type.dart';
import 'package:jmcomic3/configs/reader_direction.dart';
import 'package:jmcomic3/configs/reader_slider_position.dart';
import 'package:jmcomic3/configs/reader_type.dart';
import 'package:jmcomic3/configs/two_page_direction.dart';
import 'package:jmcomic3/configs/volume_key_control.dart';
import 'package:jmcomic3/configs/theme.dart' as app_theme;
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/comic_reader_screen.dart';
import 'package:jmcomic3/screens/components/images.dart';
import 'package:zoomable_positioned_list/zoomable_positioned_list.dart'
    as zoomable;

Future<void> Function(String name, WidgetTester tester)? readerCheckpoint;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  final heights = <int>[64, 384, 128, 512, 96, 320, 64, 384, 64, 128];
  final paths = <String>[];
  final viewLogs = <int>[];
  final imageRequests = <String>[];
  Completer<void>? imageGate;
  var direction = ReaderDirection.leftToRight;
  var controlMode = ReaderControllerType.controller;

  setUpAll(() async {
    directory = Directory(Platform.isAndroid
        ? '${Directory.systemTemp.path}/jm-reader-rewrite-fixtures'
        : 'build/reader-rewrite/fixtures');
    await directory.create(recursive: true);
    for (var index = 0; index < heights.length; index++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(Rect.fromLTWH(0, 0, 64, heights[index].toDouble()),
          Paint()..color = Colors.primaries[index]);
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
  tearDown(() async {
    if (imageGate != null && !imageGate!.isCompleted) imageGate!.complete();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('methods'), null);
  });

  Future<GlobalKey> mountReader(
      WidgetTester tester, ReaderType type, ReaderDirection readDirection,
      {int pageCount = 10,
      int startIndex = 0,
      ThemeData? theme,
      ValueChanged<int>? onUnmount}) async {
    direction = readDirection;
    await initReaderControllerType();
    await initReaderDirection();
    await initReaderSliderPosition();
    await initNoAnimation();
    await initVolumeKeyControl();
    await initTwoPageDirection();
    final key = GlobalKey();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)));
      clearAllImageMemoryCaches();
    });
    await tester.pumpWidget(_UnmountProbe(
        onDeactivate: () {
          if (key.currentState != null) {
            onUnmount?.call(comicReaderProgressForTest(key).current);
          }
        },
        child: RepaintBoundary(
            key: const ValueKey('reader-regression-surface'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              localizationsDelegates: const [AppLocalizations.delegate],
              home: Scaffold(
                  body: buildComicReaderForTest(
                key: key,
                chapter: ChapterResponse(
                    id: 81234,
                    series: [],
                    tags: '',
                    name: 'Reader regression',
                    images: List.generate(pageCount, (index) => '$index.png'),
                    seriesId: 81234,
                    isFavorite: false,
                    liked: false),
                readerType: type,
                direction: readDirection,
                startIndex: startIndex,
              )),
            ))));
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

  Finder firstPage() => find.byKey(const ValueKey('reader-page-81234-0'));

  for (final dark in [false, true]) {
    testWidgets(
        'bottom controls blend over pages with a small draggable dot ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(bottom: 24);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
      });
      if (!Platform.isAndroid &&
          Platform.environment['LAYOUT_SCREENSHOTS'] == '1') {
        await tester.runAsync(() async {
          final font = await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes();
          await (FontLoader('Roboto')
                ..addFont(Future.value(ByteData.sublistView(font))))
              .load();
          final icons = await File(
                  '_flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
              .readAsBytes();
          await (FontLoader('MaterialIcons')
                ..addFont(Future.value(ByteData.sublistView(icons))))
              .load();
        });
      }
      final key = await mountReader(
          tester, ReaderType.webToonFreeZoom, ReaderDirection.topToBottom,
          startIndex: 1,
          theme: dark ? app_theme.darkTheme : app_theme.lightTheme);
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 100; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          final image = find.descendant(
            of: find.byKey(const ValueKey('reader-page-81234-1')),
            matching: find.byType(RawImage),
          );
          if (image.evaluate().isNotEmpty &&
              tester.widget<RawImage>(image.first).image != null) break;
        }
      });
      jumpComicReaderForTest(key, 1, animation: false);
      await tester.pumpAndSettle();
      final barFinder = find.byKey(const ValueKey('reader-bottom-controls'));
      final thumbFinder = find.byKey(const ValueKey('reader-progress-thumb'));
      expect(tester.getSize(thumbFinder).width, lessThan(20));
      final viewport =
          tester.getRect(find.byType(zoomable.ZoomablePositionedList));
      final bar = tester.getRect(barFinder);
      expect(viewport.bottom, closeTo(bar.bottom, .1));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('reader-regression-surface')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          if (!Platform.isAndroid) {
            await File(
                    'build/reader-rewrite/progress-${dark ? 'dark' : 'light'}.png')
                .writeAsBytes(png!.buffer.asUint8List());
          }
          final pixels =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List();
          // Sample both the toolbar and the phone's bottom safe inset. Both
          // must show the real pink page underneath the translucent black.
          final expected =
              Color.alphaBlend(const Color(0x88000000), Colors.primaries[1]);
          for (final y in [bar.top + 4, bar.bottom - 4]) {
            final offset =
                (y.floor() * image.width + (bar.left + 4).floor()) * 4;
            expect(pixels[offset], closeTo((expected.r * 255).round(), 2));
            expect(pixels[offset + 1], closeTo((expected.g * 255).round(), 2));
            expect(pixels[offset + 2], closeTo((expected.b * 255).round(), 2));
          }
        } finally {
          image.dispose();
        }
      });
      await readerCheckpoint?.call(
          'reader-progress-${dark ? 'dark' : 'light'}', tester);
      final slider = tester.getRect(find.byType(FlutterSlider));
      await tester.timedDragFrom(tester.getCenter(thumbFinder),
          Offset(slider.width * .5, 0), const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(comicReaderProgressForTest(key).current, greaterThan(1));
      expect(tester.getSize(thumbFinder).width, lessThan(20));
      tester
          .widget<zoomable.ZoomablePositionedList>(
              find.byType(zoomable.ZoomablePositionedList))
          .itemScrollController!
          .jumpTo(index: 10);
      await tester.pumpAndSettle();
      final end = find.text('Finish reading');
      expect(end.hitTestable(), findsOneWidget);
      expect(
          tester.getRect(end).bottom, lessThan(tester.getRect(barFinder).top));
      expect(tester.takeException(), isNull);
    });
  }

  for (final type in [ReaderType.gallery, ReaderType.twoPageGallery]) {
    for (final readDirection in ReaderDirection.values) {
      testWidgets('$type $readDirection zoom/pan resets before paging',
          (tester) async {
        final key = await mountReader(tester, type, readDirection);
        final photo = tester.widget<PhotoView>(find.byType(PhotoView).first);
        final controller = photo.controller!;
        final rect = tester.getRect(find.byType(PhotoView).first);
        await doubleTap(tester, rect.center);
        expect(controller.scale, closeTo(2, .01));
        await readerCheckpoint?.call(
            'reader-${type.name}-${readDirection.name}-zoom', tester);
        final before = controller.position;
        await tester.timedDragFrom(rect.center, const Offset(-80, 0),
            const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect((controller.position.dx - before.dx).abs(), greaterThan(10));
        expect(comicReaderProgressForTest(key).current, 0);
        await doubleTap(tester, rect.center);
        expect(controller.scale, closeTo(1, .01));
        final delta = switch (readDirection) {
          ReaderDirection.leftToRight => Offset(-rect.width * .9, 0),
          ReaderDirection.rightToLeft => Offset(rect.width * .9, 0),
          ReaderDirection.topToBottom => Offset(0, -rect.height * .9),
        };
        await tester.dragFrom(rect.center, delta);
        await tester.pumpAndSettle();
        expect(comicReaderProgressForTest(key).current,
            type == ReaderType.twoPageGallery ? 2 : 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('odd final spread and restored odd source rank stay in bounds',
      (tester) async {
    final key = await mountReader(
        tester, ReaderType.twoPageGallery, ReaderDirection.rightToLeft,
        pageCount: 5, startIndex: 3);
    expect(comicReaderProgressForTest(key).current, 2);
    jumpComicReaderForTest(key, 99, animation: false);
    await tester.pumpAndSettle();
    expect(comicReaderProgressForTest(key).current, 4);
    await readerCheckpoint?.call('reader-odd-spread-last', tester);
    controlComicReaderForTest('DOWN');
    await tester.pumpAndSettle();
    expect(comicReaderProgressForTest(key).current, 4);
    expect(tester.takeException(), isNull);
  });

  for (final readDirection in [
    ReaderDirection.leftToRight,
    ReaderDirection.rightToLeft,
    ReaderDirection.topToBottom
  ]) {
    testWidgets(
        '$readDirection continuous zoom pans once and restores scrolling',
        (tester) async {
      final key =
          await mountReader(tester, ReaderType.webToonFreeZoom, readDirection);
      final viewport =
          tester.getRect(find.byType(zoomable.ZoomablePositionedList));
      final original = tester.getRect(firstPage());
      await doubleTap(tester, viewport.center);
      expect(
          tester.getRect(firstPage()).width / original.width, closeTo(2, .05));
      await readerCheckpoint?.call(
          'reader-continuous-${readDirection.name}-zoom', tester);
      final before = tester.getRect(firstPage());
      await tester.timedDragFrom(
          viewport.center,
          readDirection == ReaderDirection.leftToRight
              ? const Offset(-80, 0)
              : const Offset(80, 0),
          const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      final delta = (tester.getRect(firstPage()).left - before.left).abs();
      expect(delta, greaterThan(10));
      expect(delta, lessThan(150));
      expect(comicReaderProgressForTest(key).current, 0);
      await doubleTap(tester, viewport.center);
      expect(
          tester.getRect(firstPage()).width / original.width, closeTo(1, .05));
      final scroll = switch (readDirection) {
        ReaderDirection.topToBottom =>
          Offset(0, -original.height - viewport.height / 2),
        ReaderDirection.leftToRight =>
          Offset(-original.width - viewport.width / 3, 0),
        ReaderDirection.rightToLeft =>
          Offset(original.width + viewport.width / 3, 0),
      };
      await tester.dragFrom(viewport.center, scroll);
      await tester.pumpAndSettle();
      expect(comicReaderProgressForTest(key).current, greaterThan(0));
      await readerCheckpoint?.call(
          'reader-continuous-${readDirection.name}-restored', tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('vertical pinch keeps scale and single-finger pan after handoff',
      (tester) async {
    final key = await mountReader(
        tester, ReaderType.webToonFreeZoom, ReaderDirection.topToBottom);
    final rect = tester.getRect(find.byType(zoomable.ZoomablePositionedList));
    final initial = tester.getRect(firstPage());
    final distance = rect.width * .12;
    final first =
        await tester.createGesture(kind: PointerDeviceKind.touch, pointer: 1);
    final second =
        await tester.createGesture(kind: PointerDeviceKind.touch, pointer: 2);
    await first.down(rect.center - Offset(distance, 0));
    await second.down(rect.center + Offset(distance, 0));
    await tester.pump();
    await first.moveTo(rect.center - Offset(distance * 1.8, 0));
    await second.moveTo(rect.center + Offset(distance * 1.8, 0));
    await tester.pumpAndSettle();
    final zoomed = tester.getRect(firstPage());
    expect(zoomed.width / initial.width, greaterThan(1.1));
    await second.up();
    await tester.pump();
    final before = tester.getRect(firstPage());
    await first.moveBy(const Offset(-60, 0));
    await tester.pumpAndSettle();
    await first.up();
    final moved = tester.getRect(firstPage());
    expect(moved.width, closeTo(zoomed.width, 1));
    expect((moved.left - before.left).abs(), greaterThan(10));
    expect((moved.left - before.left).abs(), lessThan(110));
    expect(comicReaderProgressForTest(key).current, 0);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [
    ReaderControllerType.touchDouble,
    ReaderControllerType.touchDoubleOnceNext
  ]) {
    testWidgets('continuous reader preserves $mode without disabling pinch',
        (tester) async {
      controlMode = mode;
      await mountReader(
          tester, ReaderType.webToonFreeZoom, ReaderDirection.topToBottom);
      final before = tester.getRect(firstPage());
      expect(find.byType(AppBar), findsOneWidget);
      await doubleTap(tester,
          tester.getRect(find.byType(zoomable.ZoomablePositionedList)).center);
      expect(find.byType(AppBar), findsNothing);
      expect(tester.getRect(firstPage()).width, closeTo(before.width, 1));
      expect(
          tester
              .widget<zoomable.ZoomablePositionedList>(
                  find.byType(zoomable.ZoomablePositionedList))
              .enableZoom,
          isTrue);
      expect(tester.takeException(), isNull);
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
    int? actualAtRemoval;
    final key = await mountReader(
        tester, ReaderType.gallery, ReaderDirection.leftToRight,
        onUnmount: (page) => actualAtRemoval = page);
    jumpComicReaderForTest(key, 8);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final actual = comicReaderProgressForTest(key).current;
    expect(actual, lessThan(8));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    // A real Android frame may advance between sampling and pumpWidget.
    // Capture the actual page synchronously when the reader is deactivated.
    expect(actualAtRemoval, lessThan(8));
    expect(viewLogs.last, actualAtRemoval);
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

  testWidgets('reader keeps a page cache while mounted and releases it on exit',
      (tester) async {
    final readerKey = await mountReader(
        tester, ReaderType.webtoon, ReaderDirection.topToBottom);
    final firstPage = find.byType(JMPageImage).first;
    final pageFinder = find.descendant(
      of: firstPage,
      matching: find.byType(Image),
    );
    expect(pageFinder, findsOneWidget);
    final provider = tester.widget<Image>(pageFinder).image;
    final providerKey = await provider.obtainKey(ImageConfiguration.empty);
    var status = imageCache.statusForKey(providerKey);
    expect(status.live || status.keepAlive || status.pending, isTrue);

    jumpComicReaderForTest(readerKey, 5, animation: false);
    await tester.pumpAndSettle();
    status = imageCache.statusForKey(providerKey);
    expect(status.live || status.keepAlive || status.pending, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(imageCache.statusForKey(providerKey).keepAlive, isFalse);
    expect(imageCache.statusForKey(providerKey).live, isFalse);
    expect(tester.takeException(), isNull);
  });
}

class _UnmountProbe extends StatefulWidget {
  const _UnmountProbe({required this.child, required this.onDeactivate});
  final Widget child;
  final VoidCallback onDeactivate;
  @override
  State<_UnmountProbe> createState() => _UnmountProbeState();
}

class _UnmountProbeState extends State<_UnmountProbe> {
  @override
  void deactivate() {
    widget.onDeactivate();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
