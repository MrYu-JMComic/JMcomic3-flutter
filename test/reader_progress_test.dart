import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/reader_progress.dart';

void main() {
  test('estimates page and intra-page offset', () {
    final p = estimateReaderProgress(scrollOffset: 250, pageExtent: 100, pageCount: 5);
    expect(p.page, 2);
    expect(p.offset, 50);
  });

  test('clamps overscroll and invalid values', () {
    expect(estimateReaderProgress(scrollOffset: 999, pageExtent: 100, pageCount: 3).page, 2);
    expect(estimateReaderProgress(scrollOffset: double.nan, pageExtent: 100, pageCount: 3).page, 0);
    expect(estimateReaderProgress(scrollOffset: 10, pageExtent: 0, pageCount: 3).offset, 0);
  });

  test('restores legacy page-only data and clamps', () {
    final p = restoreReaderProgress({'page': 8}, pageCount: 3, pageExtent: 100);
    expect(p.page, 2);
    expect(p.offset, 0);
  });
}
