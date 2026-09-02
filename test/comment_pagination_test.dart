import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/screens/components/comic_comments_list.dart';

void main() {
  test('known totals keep pagination alive when a page is empty', () {
    expect(commentMaxPageForTotal(0), 1);
    expect(commentMaxPageForTotal(1), 1);
    expect(commentMaxPageForTotal(20), 1);
    expect(commentMaxPageForTotal(21), 2);
    expect(commentMaxPageForTotal(41), 3);
  });
}
