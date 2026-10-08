/// Returns a stable priority order for the pages around a visual viewport.
///
/// Visible pages are loaded first, followed by pages in forward reading
/// order and then the nearby pages behind the viewport.
List<int> readerPreloadOrder({
  required Iterable<int> visibleIndexes,
  required int pageCount,
  int lookAhead = 4,
  int lookBehind = 2,
}) {
  if (pageCount <= 0) {
    return const <int>[];
  }
  final visible = visibleIndexes
      .where((index) => index >= 0 && index < pageCount)
      .toSet()
      .toList()
    ..sort();
  if (visible.isEmpty) {
    return const <int>[];
  }

  final result = <int>[];
  final added = <int>{};
  void add(int index) {
    if (index >= 0 && index < pageCount && added.add(index)) {
      result.add(index);
    }
  }

  for (final index in visible) {
    add(index);
  }
  // Fill gaps when a sparse visible set is observed while a page is rebuilt.
  for (var index = visible.first; index <= visible.last; index++) {
    add(index);
  }
  final forwardCount = lookAhead.clamp(0, pageCount).toInt();
  for (var offset = 1; offset <= forwardCount; offset++) {
    add(visible.last + offset);
  }
  final behindCount = lookBehind.clamp(0, pageCount).toInt();
  for (var offset = 1; offset <= behindCount; offset++) {
    add(visible.first - offset);
  }
  return List<int>.unmodifiable(result);
}

/// 阅读器的顺序预加载任务。替换后停止旧队列，但保留已经加载的图片；
/// 只有阅读器销毁时才通过 [releaseStale] 释放迟到的解码结果。
class ReaderPreloader {
  int _generation = 0;
  bool _disposed = false;

  Future<void> preload({
    required Iterable<int> indexes,
    required Future<void> Function(int index) load,
    required void Function(int index) releaseStale,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    if (_disposed) {
      return;
    }
    final generation = ++_generation;
    final orderedIndexes = indexes.toSet().toList(growable: false);
    for (final index in orderedIndexes) {
      if (_disposed || generation != _generation) {
        return;
      }
      try {
        await load(index);
      } catch (error, stackTrace) {
        onError?.call(error, stackTrace);
      }
      if (_disposed || generation != _generation) {
        // 当前请求无法中断解码；翻页时保留已完成的图片，退出阅读器时
        // 才释放迟到的解码结果。
        if (_disposed) {
          releaseStale(index);
        }
        return;
      }
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
  }
}
