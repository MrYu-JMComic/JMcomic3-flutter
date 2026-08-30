import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/reader_progress.dart';

void main() {
  test('estimates page and intra-page offset', () {
    final p = estimateReaderProgress(
        scrollOffset: 250, pageExtent: 100, pageCount: 5);
    expect(p.page, 2);
    expect(p.offset, 50);
  });

  test('clamps overscroll and invalid values', () {
    expect(
        estimateReaderProgress(scrollOffset: 999, pageExtent: 100, pageCount: 3)
            .page,
        2);
    expect(
        estimateReaderProgress(
                scrollOffset: double.nan, pageExtent: 100, pageCount: 3)
            .page,
        0);
    expect(
        estimateReaderProgress(scrollOffset: 10, pageExtent: 0, pageCount: 3)
            .offset,
        0);
  });

  test('restores legacy page-only data and clamps', () {
    final p = restoreReaderProgress({'page': 8}, pageCount: 3, pageExtent: 100);
    expect(p.page, 2);
    expect(p.offset, 0);
  });

  test('variable page extents locate page and intra-page offset', () {
    final p = estimateVariableReaderProgress(
      scrollOffset: 260,
      pageExtents: [100, 200, 50],
    );
    expect(p.page, 1);
    expect(p.offset, 160);
    expect(offsetForReaderPage([100, 200, 50], 2), 300);
  });

  test('variable progress sanitizes invalid extents and offsets', () {
    final p = estimateVariableReaderProgress(
      scrollOffset: double.infinity,
      pageExtents: [double.nan, -1],
    );
    expect(p.page, 0);
    expect(p.offset, 0);
    expect(offsetForReaderPage([double.nan, -1], 1), 1);
  });

  test('extent index handles exact boundaries and large jumps', () {
    final index = ReaderExtentIndex([100, 200, 50]);
    final atBoundary = index.estimate(100);
    expect(atBoundary.page, 1);
    expect(atBoundary.offset, 0);
    final atEnd = index.estimate(999);
    expect(atEnd.page, 2);
    expect(atEnd.offset, 50);
    expect(index.offsetForPage(-1), 0);
    expect(index.offsetForPage(99), 350);
  });
}
