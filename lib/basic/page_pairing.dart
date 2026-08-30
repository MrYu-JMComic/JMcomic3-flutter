/// Pure Dart model for deterministic two-page reader pairing.
class PagePair {
  final int slot;
  final int? left;
  final int? right;
  const PagePair(this.slot, {this.left, this.right});
  List<int> get pages => [if (left != null) left!, if (right != null) right!];

  /// Source page represented by the leading reading position in this slot.
  /// For an RTL pair the lower source index is rendered on the right and is
  /// therefore the page the reader reaches first; callers can use this to
  /// keep progress/view-log semantics independent from visual left/right.
  int primaryPage({bool rtl = false}) =>
      (rtl ? (right ?? left) : (left ?? right)) ?? -1;
}

/// Builds visual slots without changing source page indices.
/// `cover` reserves page 0 as a solo slot; subsequent pages are paired.
/// RTL reverses visual order inside each pair while preserving indices.
List<PagePair> buildPagePairs(int pageCount,
    {bool cover = true, bool rtl = false, int startIndex = 0}) {
  if (pageCount <= 0) return const [];
  final start = startIndex.clamp(0, pageCount - 1).toInt();
  final result = <PagePair>[];
  var slot = 0;
  if (cover) {
    result.add(const PagePair(0, left: 0));
    slot = 1;
  }
  var index = cover ? 1 : 0;
  while (index < pageCount) {
    final next = index + 1 < pageCount ? index + 1 : null;
    result.add(rtl
        ? PagePair(slot++, left: next, right: index)
        : PagePair(slot++, left: index, right: next));
    index += 2;
  }
  // Keep the requested start page discoverable by callers; no hidden mutation
  // of pairing occurs. Consumers can locate its slot with pairForPage.
  assert(start >= 0 && start < pageCount);
  return List.unmodifiable(result);
}

PagePair? pairForPage(List<PagePair> pairs, int pageIndex) {
  for (final pair in pairs) {
    if (pair.left == pageIndex || pair.right == pageIndex) return pair;
  }
  return null;
}
