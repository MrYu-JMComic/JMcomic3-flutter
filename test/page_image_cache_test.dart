import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/screens/components/images.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  late Directory directory;
  late File file;
  var pageCalls = 0;
  var sizeCalls = 0;

  setUp(() async {
    clearAllImageMemoryCaches();
    imageCache.clear();
    imageCache.clearLiveImages();
    pageCalls = 0;
    sizeCalls = 0;
    directory = await Directory.systemTemp.createTemp('jm3-page-cache-');
    file = File('${directory.path}/page.png');
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.green, BlendMode.src);
    final picture = recorder.endRecording();
    final bitmap = await picture.toImage(120, 180);
    final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    bitmap.dispose();
    picture.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final payload = jsonDecode(call.arguments as String) as Map;
      Object response;
      switch (payload['method']) {
        case 'jm_page_image':
          pageCalls++;
          response = file.path;
          break;
        case 'image_size':
          sizeCalls++;
          response = jsonEncode({'w': 120, 'h': 180});
          break;
        default:
          throw StateError('Unexpected method: ${payload['method']}');
      }
      return jsonEncode({'error_message': '', 'response_data': response});
    });
  });

  tearDown(() async {
    clearAllImageMemoryCaches();
    imageCache.clear();
    imageCache.clearLiveImages();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  Future<Object> mountPage(
    WidgetTester tester, {
    double width = 120,
    double height = 180,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1),
        child: Center(
          child: JMPageImage(
            42,
            'page.png',
            width: width,
            height: height,
            onTrueSize: (_) {},
          ),
        ),
      ),
    ));
    // 使用真实文件解码；异步 I/O 在真实时钟中完成，避免只测试缓存键的字符串匹配。
    await tester.runAsync(() async {
      final expectedProvider = ResizeImage.resizeIfNeeded(
        decodeTargetExtentForTest(width, 1),
        decodeTargetExtentForTest(height, 1),
        FileImage(file),
      );
      final expectedKey =
          await expectedProvider.obtainKey(ImageConfiguration.empty);
      for (var attempt = 0; attempt < 50; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.byType(Image).evaluate().isNotEmpty &&
            imageCache.statusForKey(expectedKey).keepAlive) {
          break;
        }
      }
      expect(find.byType(Image), findsOneWidget);
      expect(imageCache.statusForKey(expectedKey).keepAlive, isTrue);
    });
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byType(Image));
    final key = await image.image.obtainKey(ImageConfiguration.empty);
    expect(imageCache.statusForKey(key).keepAlive, isTrue);
    expect(tester.takeException(), isNull);
    return key;
  }

  testWidgets('page eviction removes actual resized file cache variants',
      (tester) async {
    final largeKey = await mountPage(tester);
    // Use distinct codec buckets rather than two sizes that both map to 256.
    final smallKey = await mountPage(tester, width: 300, height: 450);
    expect(largeKey, isNot(smallKey));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(imageCache.statusForKey(largeKey).keepAlive, isTrue);
    expect(imageCache.statusForKey(smallKey).keepAlive, isTrue);

    evictPageImageDecodeCache(42, 'page.png');
    expect(imageCache.statusForKey(largeKey).keepAlive, isFalse);
    expect(imageCache.statusForKey(smallKey).keepAlive, isFalse);
    expect(imageCache.statusForKey(smallKey).live, isFalse);
    expect(pageCalls, 1);
  });

  testWidgets('page eviction preserves the currently displayed image',
      (tester) async {
    final key = await mountPage(tester);
    expect(imageCache.statusForKey(key).live, isTrue);
    evictPageImageDecodeCache(42, 'page.png');
    expect(imageCache.statusForKey(key).keepAlive, isFalse);
    expect(imageCache.statusForKey(key).live, isTrue);
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(imageCache.statusForKey(key).live, isFalse);
  });

  testWidgets('page memory eviction reloads path and size on the next visit',
      (tester) async {
    final key = await mountPage(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    evictPageImageMemoryCache(42, 'page.png');
    expect(imageCache.statusForKey(key).keepAlive, isFalse);
    await mountPage(tester);
    expect(pageCalls, 2);
    expect(sizeCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
