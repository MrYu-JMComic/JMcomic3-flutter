import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/screens/components/images.dart';

void main() {
  test('decode target is bounded to stable buckets', () {
    expect(decodeTargetExtentForTest(100, 1), 256);
    expect(decodeTargetExtentForTest(500, 1), 512);
    expect(decodeTargetExtentForTest(900, 2), 2048);
    expect(decodeTargetExtentForTest(null, 2), isNull);
    expect(decodeTargetExtentForTest(0, 2), isNull);
    expect(decodeTargetExtentForTest(10000, 4), 4096);
    expect(decodeTargetExtentForTest(double.infinity, 1), isNull);
    expect(decodeTargetExtentForTest(100, double.nan), isNull);
  });

  test('page provider key includes bounded codec targets', () {
    final small = readerPageImageProviderForTest(
      id: 1,
      imageName: 'page.jpg',
      width: 100,
      height: 200,
    );
    final same = readerPageImageProviderForTest(
      id: 1,
      imageName: 'page.jpg',
      width: 101,
      height: 201,
    );
    final different = readerPageImageProviderForTest(
      id: 1,
      imageName: 'page.jpg',
      width: 500,
      height: 200,
    );

    expect(small.cacheWidth, 256);
    expect(small.cacheHeight, 256);
    expect(small, same);
    expect(small, isNot(different));
    expect(small.hashCode, same.hashCode);
  });
}
