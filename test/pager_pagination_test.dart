import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/screens/components/pager_pagination.dart';

void main() {
  group('calcMaxPageFromTotal', () {
    test('uses the explicit page capacity for favorite pages', () {
      expect(calcMaxPageFromTotal(87, 20), 5);
    });

    test('keeps an exact multiple on its final page', () {
      expect(calcMaxPageFromTotal(80, 20), 4);
    });

    test('keeps an empty result on page one', () {
      expect(calcMaxPageFromTotal(0, 20), 1);
    });

    test('falls back to page one when page capacity is missing', () {
      expect(calcMaxPageFromTotal(87, 0), 1);
    });

    test('calculates large totals without floating point rounding', () {
      expect(calcMaxPageFromTotal(9007199254740993, 20), 450359962737050);
    });
  });
}
