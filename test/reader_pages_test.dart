import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/reader_pages.dart';

void main() {
  test('local availability is opt-in and independent of page name', () {
    const page = PageDescriptor(position: 0, name: '1.jpg');
    expect(page.localPath, isNull);
    expect(page.localAvailable, isFalse);
    final resolved = page.copyWith(
      localPath: 'C:/cache/1.jpg',
      localAvailable: true,
    );
    expect(resolved.localAvailable, isTrue);
    expect(resolved.localPath, 'C:/cache/1.jpg');
  });
}
