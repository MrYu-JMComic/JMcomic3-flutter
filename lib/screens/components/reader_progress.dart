import 'dart:math';

/// 页面在阅读视口中的相对边界，0 为视口起点，1 为终点。
class ReaderPageBounds {
  final int index;
  final double leading;
  final double trailing;

  const ReaderPageBounds(this.index, this.leading, this.trailing);
}

/// 优先选择覆盖视口中心的图片，超长图片尾部仍在中心时不会提前跳到下一张短图。
int? readerPageAtViewportCenter(Iterable<ReaderPageBounds> pages) {
  int? selected;
  var bestDistance = double.infinity;
  var bestVisible = -1.0;
  for (final page in pages) {
    if (page.trailing <= 0 || page.leading >= 1) {
      continue;
    }
    final distance = page.leading > 0.5
        ? page.leading - 0.5
        : page.trailing < 0.5
            ? 0.5 - page.trailing
            : 0.0;
    final visible = min(page.trailing, 1.0) - max(page.leading, 0.0);
    if (distance < bestDistance ||
        (distance == bestDistance && visible > bestVisible)) {
      selected = page.index;
      bestDistance = distance;
      bestVisible = visible;
    }
  }
  return selected;
}
