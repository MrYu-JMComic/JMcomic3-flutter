import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/screens/components/pager_pagination.dart';
import 'package:jmcomic3/basic/entities.dart';

void main() {
  group('calcMaxPageFromTotal', () {
    test('local history preserves its explicit 80-item capacity', () {
      final response = ComicsResponse.fromJson({
        'total': 165,
        'page_size': '80',
        'content': [
          {'id': 161, 'name': 'Last page item'}
        ],
      });
      final page = InnerComicPage(
          total: response.total,
          list: response.content,
          pageSize: response.pageSize);
      expect(page.effectivePageSize, 80);
      expect(calcMaxPageFromTotal(page.total, page.effectivePageSize), 3);
      expect(response.toJson()['page_size'], 80);
    });
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
