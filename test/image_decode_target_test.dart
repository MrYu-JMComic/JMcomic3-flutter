import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/screens/components/images.dart';

void main() {
  test('decode target is bounded to stable buckets', () {
    expect(decodeTargetExtentForTest(100, 1), 256);
    expect(decodeTargetExtentForTest(500, 1), 512);
    expect(decodeTargetExtentForTest(900, 2), 2048);
    expect(decodeTargetExtentForTest(null, 2), isNull);
    expect(decodeTargetExtentForTest(0, 2), isNull);
  });
}
