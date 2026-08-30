/// Pure reader progress model. Offset is measured in logical pixels within
/// the current page; callers may correct it after layout/scroll metrics settle.
class ReaderProgress {
  const ReaderProgress({required this.page, required this.offset});
  final int page;
  final double offset;

  ReaderProgress clamp({required int pageCount, required double pageExtent}) {
    final maxPage = pageCount <= 0 ? 0 : pageCount - 1;
    final safeExtent = pageExtent.isFinite && pageExtent > 0 ? pageExtent : 0;
    final p = page.clamp(0, maxPage);
    final o = safeExtent == 0
        ? 0.0
        : offset.clamp(0.0, safeExtent).toDouble();
    return ReaderProgress(page: p, offset: o);
  }
}

/// Estimates a visible page from scroll position. Invalid/legacy values fall
/// back to page zero rather than producing NaN or an out-of-range index.
ReaderProgress estimateReaderProgress({
  required double scrollOffset,
  required double pageExtent,
  required int pageCount,
}) {
  if (pageCount <= 0 || !scrollOffset.isFinite ||
      !pageExtent.isFinite || pageExtent <= 0) {
    return const ReaderProgress(page: 0, offset: 0);
  }
  final safeOffset = scrollOffset < 0 ? 0.0 : scrollOffset;
  final rawPage = (safeOffset / pageExtent).floor();
  final page = rawPage.clamp(0, pageCount - 1);
  final offset = safeOffset - rawPage * pageExtent;
  return ReaderProgress(page: page, offset: offset)
      .clamp(pageCount: pageCount, pageExtent: pageExtent);
}

/// Restores persisted progress, accepting older page-only records.
ReaderProgress restoreReaderProgress(
  Map<String, dynamic>? data, {
  required int pageCount,
  required double pageExtent,
}) {
  final page = data?['page'] is num ? (data!['page'] as num).toInt() : 0;
  final offset = data?['offset'] is num
      ? (data!['offset'] as num).toDouble()
      : 0.0;
  return ReaderProgress(page: page, offset: offset)
      .clamp(pageCount: pageCount, pageExtent: pageExtent);
}
