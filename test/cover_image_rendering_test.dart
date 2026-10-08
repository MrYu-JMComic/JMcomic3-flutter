import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/screens/components/images.dart';

const _channel = MethodChannel('methods');
const _captureKey = ValueKey('cover-render');

Future<File> _sourceImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Colors.blue);
  canvas.drawCircle(Offset(width / 2, height / 2),
      (width < height ? width : height) / 4, Paint()..color = Colors.red);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  // Keep generated fixtures in the ignored build directory. Windows image
  // codecs can retain file handles briefly after a test has finished.
  final file = File('build/cover-rendering/source-$width-$height.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return file.absolute;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var comicId = 93000;
  for (final square in [false, true]) {
    for (final sourceSize in const [
      Size(1200, 400),
      Size(400, 1200),
      Size(800, 800)
    ]) {
      final id = comicId++;
      final label = '${square ? 'square' : '3x4'} '
          '${sourceSize.width.toInt()}x${sourceSize.height.toInt()}';
      testWidgets('$label cover scales and crops without stretching pixels',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        final file = await tester.runAsync(() =>
            _sourceImage(sourceSize.width.toInt(), sourceSize.height.toInt()));
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(_channel, (call) async {
          final request = jsonDecode(call.arguments as String) as Map;
          expect(
              request['method'], square ? 'jm_square_cover' : 'jm_3x4_cover');
          return jsonEncode({'error_message': '', 'response_data': file!.path});
        });
        clearAllImageMemoryCaches();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          clearAllImageMemoryCaches();
          messenger.setMockMethodCallHandler(_channel, null);
        });

        final size = square ? const Size(100, 100) : const Size(90, 120);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: _captureKey,
                child: SizedBox.fromSize(
                  size: size,
                  child: square
                      ? JMSquareCover(
                          comicId: id, width: size.width, height: size.height)
                      : JM3x4Cover(
                          comicId: id, width: size.width, height: size.height),
                ),
              ),
            ),
          ),
        ));
        await tester.runAsync(() async {
          for (var attempt = 0; attempt < 100; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump();
            final images = find.byType(RawImage);
            if (images.evaluate().isNotEmpty &&
                tester.widget<RawImage>(images.first).image != null) {
              break;
            }
          }
        });
        await tester.pumpAndSettle();
        final raw = tester.widget<RawImage>(find.byType(RawImage));
        expect(raw.image, isNotNull);
        expect(raw.fit, BoxFit.cover);

        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
        await tester.runAsync(() async {
          final rendered = await boundary.toImage(pixelRatio: 1);
          try {
            final png =
                await rendered.toByteData(format: ui.ImageByteFormat.png);
            final name = label.replaceAll(' ', '-');
            await File('build/cover-rendering/$name.png')
                .writeAsBytes(png!.buffer.asUint8List());
            final pixels =
                (await rendered.toByteData(format: ui.ImageByteFormat.rawRgba))!
                    .buffer
                    .asUint8List();
            int minX = rendered.width,
                minY = rendered.height,
                maxX = -1,
                maxY = -1;
            for (var y = 0; y < rendered.height; y++) {
              for (var x = 0; x < rendered.width; x++) {
                final offset = (y * rendered.width + x) * 4;
                if (pixels[offset] > 200 &&
                    pixels[offset + 1] < 120 &&
                    pixels[offset + 2] < 120) {
                  if (x < minX) minX = x;
                  if (x > maxX) maxX = x;
                  if (y < minY) minY = y;
                  if (y > maxY) maxY = y;
                }
              }
            }
            expect(maxX, greaterThan(minX));
            expect((maxX - minX + 1) / (maxY - minY + 1), closeTo(1, .05),
                reason:
                    'An original circle must remain round, not become an ellipse.');
            final corner = (2 * rendered.width + 2) * 4;
            expect(pixels[corner], lessThan(80));
            expect(pixels[corner + 2], greaterThan(180),
                reason: 'BoxFit.cover must fill/crop, not add letterboxing.');
          } finally {
            rendered.dispose();
          }
        });
        expect(raw.image!.width, sourceSize.width.toInt());
        expect(raw.image!.height, sourceSize.height.toInt());
        expect(tester.takeException(), isNull);
      });
    }
  }
}
