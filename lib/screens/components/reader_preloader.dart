/// 阅读器的顺序预加载任务。替换或销毁后只等待正在加载的一张图，随后停止旧队列。
class ReaderPreloader {
  int _generation = 0;
  bool _disposed = false;
  Set<int> _activeIndexes = {};

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
    _activeIndexes = indexes.toSet();
    final orderedIndexes = _activeIndexes.toList(growable: false);
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
        // 当前请求无法中断解码；完成后释放已离开新窗口的图片，并中止剩余旧队列。
        if (_disposed || !_activeIndexes.contains(index)) {
          releaseStale(index);
        }
        return;
      }
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _activeIndexes = {};
  }
}
