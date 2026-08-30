import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/screens/components/images.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('target codec produces bounded pixels from a canonical fixture',
      () async {
    final fixture = File('images/reader_screen.png');
    final bytes = await fixture.readAsBytes();
    final codec = await decodeCanonicalPageBytesForTest(
      bytes,
      cacheWidth: 256,
    );
    final frame = await codec.getNextFrame();

    // The fixture is 421x751. Target decoding must reduce the bitmap while
    // retaining its aspect ratio; no scrambled/network bytes are involved in
    // this step.
    expect(frame.image.width, 256);
    expect(frame.image.height, 456);
    expect(frame.image.height / frame.image.width, closeTo(751 / 421, 0.03));
    codec.dispose();
  });
}
