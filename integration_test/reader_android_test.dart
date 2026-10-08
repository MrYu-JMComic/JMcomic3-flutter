import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:another_xlider/another_xlider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

import '../test/favorites_pagination_widget_test.dart' as favorites;
import '../test/week_screen_test.dart' as weekly;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // 使用设备真实帧调度，覆盖手势与动画竞争，而不是桌面测试的虚拟时钟。
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  binding.reportData = {
    'platform': Platform.operatingSystem,
    'device_id': const String.fromEnvironment('READER_TEST_DEVICE_ID'),
    'reader_checks': <Map<String, Object?>>[],
  };
  tearDownAll(() {
    binding.reportData!['test_results'] = binding.results.map((name, result) =>
        MapEntry(name, result is String ? result : 'failure'));
  });

  // 各组独立注册钩子，避免阅读器的模拟通道覆盖收藏和周刊响应。
  group('Android favorites pagination', favorites.main);
  group('Android weekly issue refresh', weekly.main);
  group('Android reader gestures and lifecycle', () {
    final fixture = _ReaderDeviceFixture(binding);
    setUpAll(fixture.createImages);
    tearDownAll(fixture.deleteImages);
    setUp(fixture.prepare);
    tearDown(fixture.cleanUp);

    testWidgets('horizontal double tap, single finger pan and restored paging',
        (tester) async {
      final key = await fixture.mount(
          tester, ReaderType.webToonFreeZoom, ReaderDirection.leftToRight);
      final viewerFinder = find.byType(InteractiveViewer).first;
      final rect = tester.getRect(viewerFinder);
      final center = rect.center;
      final controller = tester
          .widget<InteractiveViewer>(viewerFinder)
          .transformationController!;
      await _doubleTap(tester, center);
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.9));
      final before = controller.value.storage[12];
      await tester.dragFrom(center, Offset(rect.width * .25, 0));
      await _settle(tester);
      expect((controller.value.storage[12] - before).abs(), greaterThan(10));
      expect(comicReaderProgressForTest(key).current, 0);
      fixture.record('horizontal_single_finger_pan', key, {
        'translation_delta': controller.value.storage[12] - before,
      });
      await _doubleTap(tester, center);
      await tester.dragFrom(
        Offset(rect.left + rect.width * .8, center.dy),
        Offset(-rect.width * .7, 0),
      );
      await _settle(tester);
      expect(comicReaderProgressForTest(key).current, 1);
      await fixture.screenshot(tester, 'reader_horizontal_paging_restored');
      expect(tester.takeException(), isNull);
    });

    testWidgets('vertical double tap, single finger pan and restored scrolling',
        (tester) async {
      final key = await fixture.mount(
          tester, ReaderType.webToonFreeZoom, ReaderDirection.topToBottom);
      final viewerFinder = find.byType(InteractiveViewer);
      final rect = tester.getRect(viewerFinder);
      final center = rect.center;
      final controller = tester
          .widget<InteractiveViewer>(viewerFinder)
          .transformationController!;
      final current = comicReaderProgressForTest(key).current;
      await _doubleTap(tester, center);
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.9));
      final before = controller.value.storage[12];
      await tester.dragFrom(center, Offset(rect.width * .2, 0));
      await _settle(tester);
      expect((controller.value.storage[12] - before).abs(), greaterThan(10));
      expect(comicReaderProgressForTest(key).current, current);
      fixture.record('vertical_single_finger_pan', key, {
        'translation_delta': controller.value.storage[12] - before,
      });
      await fixture.screenshot(tester, 'reader_vertical_zoom_pan');
      await _doubleTap(tester, center);
      expect(controller.value.getMaxScaleOnAxis(), closeTo(1, .001));
      expect(
          tester.widget<InteractiveViewer>(viewerFinder).panEnabled, isFalse);
      await tester.dragFrom(
        Offset(center.dx, rect.top + rect.height * .75),
        Offset(0, -rect.height * .6),
      );
      await _settle(tester);
      expect(comicReaderProgressForTest(key).current, greaterThan(current));
      expect(tester.takeException(), isNull);
    });

    testWidgets('vertical pinch handoff keeps single finger horizontal pan',
        (tester) async {
      final key = await fixture.mount(
          tester, ReaderType.webToonFreeZoom, ReaderDirection.topToBottom);
      final viewerFinder = find.byType(InteractiveViewer);
      final rect = tester.getRect(viewerFinder);
      final controller = tester
          .widget<InteractiveViewer>(viewerFinder)
          .transformationController!;
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
      await _settle(tester);
      await first.moveTo(Offset(rect.center.dx - 150, rect.center.dy));
      await second.moveTo(Offset(rect.center.dx + 150, rect.center.dy));
      await _settle(tester);
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.1));

      await second.up();
      await tester.pump();
      expect(
          tester.widget<InteractiveViewer>(viewerFinder).panEnabled, isFalse);
      final before = controller.value.storage[12];
      await first.moveBy(const Offset(-100, 0));
      await _settle(tester);
      await first.up();
      final delta = (controller.value.storage[12] - before).abs();
      expect(delta, greaterThan(10));
      expect(delta, lessThan(180));
      expect(comicReaderProgressForTest(key).current, 0);
      expect(tester.takeException(), isNull);
      fixture.record('vertical_pinch_handoff', key, {
        'translation_delta': controller.value.storage[12] - before,
      });
    });

    for (final type in [
      ReaderType.gallery,
      ReaderType.webToonFreeZoom,
      ReaderType.twoPageGallery,
    ]) {
      testWidgets('$type slider retains the newest animated target',
          (tester) async {
        final key =
            await fixture.mount(tester, type, ReaderDirection.leftToRight);
        jumpComicReaderForTest(key, 8);
        await tester.pump(const Duration(milliseconds: 65));
        final first = comicReaderProgressForTest(key);
        expect(first.slider, 8);
        expect(first.jumpTarget, 8);
        expect(first.current, isNot(8));
        expect(
          tester
              .widget<FlutterSlider>(find.byType(FlutterSlider))
              .values
              .single,
          8,
        );
        jumpComicReaderForTest(key, 4);
        final samples = <Map<String, Object?>>[];
        for (var tick = 0; tick < 3; tick++) {
          await tester.pump(const Duration(milliseconds: 55));
          final progress = comicReaderProgressForTest(key);
          expect(progress.slider, 4);
          samples.add({
            'current': progress.current,
            'slider': progress.slider,
            'jump_target': progress.jumpTarget,
          });
        }
        expect(samples.any((sample) => sample['jump_target'] == 4), isTrue);
        await _settle(tester);
        expect(comicReaderProgressForTest(key),
            (current: 4, slider: 4, jumpTarget: null));
        fixture
            .record('latest_target_$type', key, {'animation_samples': samples});
        if (type == ReaderType.gallery) {
          await fixture.screenshot(tester, 'reader_slider_newest_target');
        }
        expect(tester.takeException(), isNull);
      });
    }

    for (final type in [ReaderType.webtoon, ReaderType.webToonFreeZoom]) {
      testWidgets('$type jumps precisely across images of different heights',
          (tester) async {
        final key =
            await fixture.mount(tester, type, ReaderDirection.topToBottom);
        jumpComicReaderForTest(key, 7, animation: false);
        await _waitFor(
            tester, () => comicReaderProgressForTest(key).jumpTarget == null);
        await _settle(tester);
        expect(comicReaderProgressForTest(key),
            (current: 7, slider: 7, jumpTarget: null));
        jumpComicReaderForTest(key, 2);
        await tester.pump(const Duration(milliseconds: 65));
        expect(comicReaderProgressForTest(key).slider, 2);
        await _settle(tester);
        expect(comicReaderProgressForTest(key).current, 2);
        fixture.record('variable_height_jump_$type', key);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('rapid two-page controls retain spread targets at boundaries',
        (tester) async {
      final key = await fixture.mount(
          tester, ReaderType.twoPageGallery, ReaderDirection.leftToRight);
      controlComicReaderForTest('DOWN');
      await tester.pump(const Duration(milliseconds: 60));
      controlComicReaderForTest('DOWN');
      await tester.pump(const Duration(milliseconds: 60));
      expect(comicReaderProgressForTest(key).slider, 4);
      controlComicReaderForTest('UP');
      await tester.pump(const Duration(milliseconds: 50));
      controlComicReaderForTest('UP');
      await _settle(tester);
      expect(comicReaderProgressForTest(key),
          (current: 0, slider: 0, jumpTarget: null));
      controlComicReaderForTest('UP');
      await _settle(tester);
      expect(comicReaderProgressForTest(key).current, 0);
      for (var index = 0; index < 6; index++) {
        controlComicReaderForTest('DOWN');
        await _settle(tester);
      }
      expect(comicReaderProgressForTest(key).current, 8);
      fixture.record('two_page_boundaries', key);
      expect(tester.takeException(), isNull);
    });

    testWidgets('exit during animation persists the visible page',
        (tester) async {
      final key = await fixture.mount(
          tester, ReaderType.gallery, ReaderDirection.leftToRight);
      jumpComicReaderForTest(key, 8);
      await tester.pump(const Duration(milliseconds: 65));
      final actual = comicReaderProgressForTest(key).current;
      expect(actual, lessThan(8));
      await fixture.close(tester);
      await _waitFor(tester, () => fixture.viewLogs.isNotEmpty);
      expect(fixture.viewLogs.last, actual);
      fixture.recordValues('exit_visible_page', {
        'visible_page': actual,
        'persisted_page': fixture.viewLogs.last,
      });
      expect(tester.takeException(), isNull);
    });

    for (final type in [ReaderType.gallery, ReaderType.webToonFreeZoom]) {
      testWidgets('$type releases real decoded images on exit', (tester) async {
        await fixture.mount(
            tester,
            type,
            type == ReaderType.gallery
                ? ReaderDirection.leftToRight
                : ReaderDirection.topToBottom);
        if (type == ReaderType.gallery) {
          await _waitFor(tester, () => fixture.imageRequests.length >= 3);
          expect(fixture.imageRequests.take(3), ['0.png', '1.png', '2.png']);
          expect(fixture.imageRequests.toSet().length,
              fixture.imageRequests.length);
        }
        await _waitFor(tester, () => imageCache.pendingImageCount == 0);
        final before = imageCache.currentSizeBytes;
        expect(before, greaterThan(0));
        await fixture.close(tester);
        await _waitFor(tester, _imageCacheIsEmpty);
        fixture.recordValues('exit_decode_cache_$type', {
          'bytes_before': before,
          'bytes_after': imageCache.currentSizeBytes,
          'pending_after': imageCache.pendingImageCount,
          'live_after': imageCache.liveImageCount,
          'request_order': fixture.imageRequests.toList(),
        });
        await fixture.screenshot(tester, 'reader_exit_cache_${type.name}');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('late image completion after exit does not restart preload',
        (tester) async {
      fixture.imageGate = Completer<void>();
      await fixture.mount(
          tester, ReaderType.gallery, ReaderDirection.leftToRight,
          waitForDecode: false);
      await _waitFor(tester, () => fixture.imageRequests.isNotEmpty);
      expect(fixture.imageRequests, ['0.png']);
      final decoded = Completer<void>();
      final stream =
          PageImageProvider(81234, '0.png').resolve(ImageConfiguration.empty);
      late ImageStreamListener listener;
      // 观察同一真实解码流并在完成时撤销监听，确认迟到结果确实经过引擎。
      listener = ImageStreamListener((info, synchronousCall) {
        info.dispose();
        stream.removeListener(listener);
        decoded.complete();
      }, onError: (Object error, StackTrace? stack) {
        decoded.completeError(error, stack);
      });
      stream.addListener(listener);
      addTearDown(() => stream.removeListener(listener));
      await fixture.close(tester);
      fixture.imageGate!.complete();
      await _waitFor(tester, () => fixture.completedImages.contains('0.png'));
      await decoded.future.timeout(const Duration(seconds: 8));
      await tester.pump();
      await _waitFor(tester, _imageCacheIsEmpty);
      final status = imageCache.statusForKey(PageImageProvider(81234, '0.png'));
      expect(status.keepAlive, isFalse);
      expect(status.pending, isFalse);
      expect(fixture.imageRequests, ['0.png']);
      fixture.recordValues('late_completion', {
        'request_order': fixture.imageRequests.toList(),
        'keep_alive': status.keepAlive,
        'pending': status.pending,
        'engine_decode_completed': decoded.isCompleted,
      });
      expect(tester.takeException(), isNull);
    });
  });
}

bool _imageCacheIsEmpty() =>
    imageCache.currentSizeBytes == 0 &&
    imageCache.pendingImageCount == 0 &&
    imageCache.liveImageCount == 0;

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
      const Duration(milliseconds: 40),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 8),
    );

// 等待设备真实 I/O 条件，使用有界轮询避免依赖固定的解码速度。
Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > const Duration(seconds: 8)) {
      fail('Device condition did not complete within 8 seconds');
    }
    await tester.pump(const Duration(milliseconds: 40));
  }
  await tester.pump();
}

Future<void> _doubleTap(WidgetTester tester, Offset point) async {
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(point);
  await _settle(tester);
}

class _ReaderDeviceFixture {
  _ReaderDeviceFixture(this.binding);

  final IntegrationTestWidgetsFlutterBinding binding;
  final heights = <int>[64, 384, 128, 512, 96, 320, 64, 384, 64, 128];
  final paths = <String>[];
  final viewLogs = <int>[];
  final imageRequests = <String>[];
  final completedImages = <String>[];
  late Directory directory;
  ReaderDirection direction = ReaderDirection.leftToRight;
  Completer<void>? imageGate;
  WidgetTester? activeTester;

  Future<void> createImages() async {
    directory = await Directory.systemTemp.createTemp('jm_reader_android_');
    // 在应用缓存目录生成可见网格图片，验证真实文件解码及异高长图布局。
    for (var index = 0; index < heights.length; index++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(Rect.fromLTWH(0, 0, 64, heights[index].toDouble()),
          Paint()..color = Colors.primaries[index]);
      for (var y = 0; y < heights[index]; y += 32) {
        canvas.drawRect(Rect.fromLTWH(0, y.toDouble(), 24, 16),
            Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(40, y.toDouble() + 16, 24, 16),
            Paint()..color = Colors.black);
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, heights[index]);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final path = '${directory.path}/page_$index.png';
      await File(path).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
      paths.add(path);
    }
  }

  Future<void> deleteImages() => directory.delete(recursive: true);

  void prepare() {
    clearAllImageMemoryCaches();
    imageCache.clear();
    imageCache.clearLiveImages();
    viewLogs.clear();
    imageRequests.clear();
    completedImages.clear();
    imageGate = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('methods'), (call) async {
      final payload = jsonDecode(call.arguments as String) as Map;
      final params = payload['params'] as String;
      var response = '';
      switch (payload['method']) {
        case 'load_property':
          response = switch (params) {
            'reader_controller_type' =>
              ReaderControllerType.controller.toString(),
            'readerDirection' => direction.toString(),
            'reader_slider_position' => ReaderSliderPosition.bottom.toString(),
            _ => '',
          };
          break;
        case 'jm_page_image':
          final name = (jsonDecode(params) as Map)['image_name'] as String;
          imageRequests.add(name);
          if (name == '0.png' && imageGate != null) {
            await imageGate!.future;
          }
          response = paths[int.parse(name.split('.').first)];
          completedImages.add(name);
          break;
        case 'image_size':
          response = jsonEncode({'w': 64, 'h': heights[paths.indexOf(params)]});
          break;
        case 'update_view_log':
          viewLogs.add((jsonDecode(params) as Map)['last_view_page'] as int);
          break;
        default:
          throw StateError(
              'Unexpected Android reader method: ${payload['method']}');
      }
      return jsonEncode({'error_message': '', 'response_data': response});
    });
  }

  Future<GlobalKey> mount(
    WidgetTester tester,
    ReaderType type,
    ReaderDirection readDirection, {
    bool waitForDecode = true,
  }) async {
    activeTester = tester;
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
            name: 'Android reader regression',
            images: List.generate(heights.length, (index) => '$index.png'),
            seriesId: 81234,
            isFavorite: false,
            liked: false,
          ),
          readerType: type,
          direction: readDirection,
        ),
      ),
    ));
    if (waitForDecode) {
      await _waitFor(tester, () => imageCache.currentSizeBytes > 0);
      await _settle(tester);
    } else {
      await tester.pump();
    }
    final view = tester.view;
    binding.reportData!['viewport'] = {
      'width': view.physicalSize.width / view.devicePixelRatio,
      'height': view.physicalSize.height / view.devicePixelRatio,
      'device_pixel_ratio': view.devicePixelRatio,
    };
    return key;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: Text('Reader closed'))),
    ));
    await tester.pump();
  }

  Future<void> cleanUp() async {
    if (activeTester != null) {
      await close(activeTester!);
      await activeTester!.pump(const Duration(milliseconds: 80));
      activeTester = null;
    }
    if (imageGate != null && !imageGate!.isCompleted) {
      imageGate!.complete();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('methods'), null);
  }

  void record(String name, GlobalKey key, [Map<String, Object?>? values]) {
    final progress = comicReaderProgressForTest(key);
    recordValues(name, {
      'current': progress.current,
      'slider': progress.slider,
      'jump_target': progress.jumpTarget,
      ...?values,
    });
  }

  void recordValues(String name, Map<String, Object?> values) {
    (binding.reportData!['reader_checks'] as List)
        .add({'name': name, ...values});
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    final bytes = await binding.takeScreenshot(name);
    expect(bytes, isNotEmpty);
  }
}
