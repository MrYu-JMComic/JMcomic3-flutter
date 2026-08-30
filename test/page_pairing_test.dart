import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/page_pairing.dart';

void main() {
  test('cover and odd tail', () {
    final pairs = buildPagePairs(5);
    expect(pairs.map((p) => p.pages).toList(), [[0], [1, 2], [3, 4]]);
    expect(pairForPage(pairs, 4)?.slot, 2);
  });
  test('without cover and RTL reverses visual order', () {
    expect(buildPagePairs(3, cover: false).map((p) => p.pages).toList(),
        [[0, 1], [2]]);
    expect(buildPagePairs(3, cover: false, rtl: true)
        .map((p) => p.pages).toList(), [[1, 0], [2]]);
  });
  test('start index is clamped without changing source indices', () {
    final pairs = buildPagePairs(2, startIndex: 99);
    expect(pairs.map((p) => p.pages).toList(), [[0], [1]]);
  });
}
