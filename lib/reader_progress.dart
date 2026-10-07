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
    final o = safeExtent == 0 ? 0.0 : offset.clamp(0.0, safeExtent).toDouble();
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
  if (pageCount <= 0 ||
      !scrollOffset.isFinite ||
      !pageExtent.isFinite ||
      pageExtent <= 0) {
    return const ReaderProgress(page: 0, offset: 0);
  }
  final safeOffset = scrollOffset < 0 ? 0.0 : scrollOffset;
  final rawPage = (safeOffset / pageExtent).floor();
  final page = rawPage.clamp(0, pageCount - 1);
  final offset = safeOffset - rawPage * pageExtent;
  return ReaderProgress(page: page, offset: offset)
      .clamp(pageCount: pageCount, pageExtent: pageExtent);
}

/// Estimates progress for a list whose pages have different extents.  Unknown
/// or invalid extents are replaced with [fallbackExtent], so a single bad
/// image-size response cannot produce NaN or make the reader jump backwards.
class ReaderExtentIndex {
  ReaderExtentIndex(
    List<double> pageExtents, {
    double fallbackExtent = 1,
  })  : _extents = _sanitizeExtents(pageExtents, fallbackExtent),
        _prefix = _buildPrefix(_sanitizeExtents(pageExtents, fallbackExtent));

  final List<double> _extents;
  final List<double> _prefix;

  int get pageCount => _extents.length;

  ReaderProgress estimate(double scrollOffset) {
    if (_extents.isEmpty || !scrollOffset.isFinite) {
      return const ReaderProgress(page: 0, offset: 0);
    }
    final safeOffset = scrollOffset < 0 ? 0.0 : scrollOffset;
    // Find the greatest page start <= offset.  Prefix has one extra terminal
    // value, so the result is naturally clamped to the final page.
    var low = 0;
    var high = _extents.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_prefix[mid + 1] <= safeOffset && mid + 1 < _extents.length) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final page = low.clamp(0, _extents.length - 1).toInt();
    final offset = safeOffset - _prefix[page];
    return ReaderProgress(page: page, offset: offset).clamp(
      pageCount: _extents.length,
      pageExtent: _extents[page],
    );
  }

  double offsetForPage(int page) {
    if (_extents.isEmpty) return 0;
    final safePage = page.clamp(0, _extents.length).toInt();
    return _prefix[safePage];
  }
}

List<double> _sanitizeExtents(List<double> values, double fallbackExtent) {
  final safeFallback =
      fallbackExtent.isFinite && fallbackExtent > 0 ? fallbackExtent : 1.0;
  return values
      .map((value) => value.isFinite && value > 0 ? value : safeFallback)
      .toList(growable: false);
}

List<double> _buildPrefix(List<double> values) {
  final prefix = List<double>.filled(values.length + 1, 0.0);
  for (var i = 0; i < values.length; i++) {
    prefix[i + 1] = prefix[i] + values[i];
  }
  return List.unmodifiable(prefix);
}

ReaderProgress estimateVariableReaderProgress({
  required double scrollOffset,
  required List<double> pageExtents,
  double fallbackExtent = 1,
}) {
  return ReaderExtentIndex(
    pageExtents,
    fallbackExtent: fallbackExtent,
  ).estimate(scrollOffset);
}

/// Returns the scroll offset at the start of [page].  This is used for a
/// second pass after a long-distance jump when real page heights are known.
double offsetForReaderPage(
  List<double> pageExtents,
  int page, {
  double fallbackExtent = 1,
}) {
  return ReaderExtentIndex(
    pageExtents,
    fallbackExtent: fallbackExtent,
  ).offsetForPage(page);
}

/// Restores persisted progress, accepting older page-only records.
ReaderProgress restoreReaderProgress(
  Map<String, dynamic>? data, {
  required int pageCount,
  required double pageExtent,
}) {
  final page = data?['page'] is num ? (data!['page'] as num).toInt() : 0;
  final offset =
      data?['offset'] is num ? (data!['offset'] as num).toDouble() : 0.0;
  return ReaderProgress(page: page, offset: offset)
      .clamp(pageCount: pageCount, pageExtent: pageExtent);
}
