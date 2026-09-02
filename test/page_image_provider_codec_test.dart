import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/screens/components/images.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'target codec produces bounded pixels from a canonical fixture',
    () async {
      final fixture = File('images/reader_screen.png');
      final provider = PageImageProvider(
        9001,
        'fixture.png',
        localPath: fixture.path,
        cacheWidth: 256,
      );
      final codec = await provider.loadCodecForTest();
      final frame = await codec.getNextFrame();

      // The fixture is 421x751. Target decoding must reduce the bitmap while
      // retaining its aspect ratio; no scrambled/network bytes are involved in
      // this step.
      expect(frame.image.width, 256);
      // Codec implementations may round the proportional target either way.
      expect(frame.image.height, anyOf(456, 457));
      expect(frame.image.height / frame.image.width, closeTo(751 / 421, 0.03));
      codec.dispose();
    },
  );

  test('buffer codec fits a portrait fixture inside both bounds', () async {
    final fixture = File('images/reader_screen.png');
    final provider = PageImageProvider(
      9002,
      'fixture.png',
      localPath: fixture.path,
      cacheWidth: 256,
      cacheHeight: 256,
    );
    final codec = await provider.loadBufferCodecForTest();
    final frame = await codec.getNextFrame();

    // The fixture is 421x751. The height is the limiting edge, so the legacy
    // buffer decoder must retain its ratio and fit within 256x256 instead of
    // decoding a 256px-wide image that exceeds the requested height.
    expect(frame.image.width, lessThanOrEqualTo(256));
    expect(frame.image.height, lessThanOrEqualTo(256));
    expect(frame.image.height, 256);
    expect(frame.image.width, anyOf(143, 144));
    expect(frame.image.height / frame.image.width, closeTo(751 / 421, 0.03));
    codec.dispose();
  });
}
