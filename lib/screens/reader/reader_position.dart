import 'dart:async';

/// Actual visible page is the persisted position. A requested jump and a
/// slider preview are temporary UI intent, never an optimistic read receipt.
class ReaderPosition {
  ReaderPosition(this.pageCount, int initialPage)
      : assert(pageCount > 0),
        _current = initialPage.clamp(0, pageCount - 1).toInt();

  final int pageCount;
  int _current;
  int get current => _current;
  int? target;
  int? preview;
  int _revision = 0;

  int get displayPage => preview ?? target ?? current;
  int get navigationPage => target ?? current;
  int clamp(int page) => page.clamp(0, pageCount - 1).toInt();

  int request(int page) {
    target = clamp(page);
    preview = null;
    return ++_revision;
  }

  bool isCurrent(int revision) => revision == _revision;

  bool report(int page) {
    final next = clamp(page);
    final changed = current != next;
    _current = next;
    if (target == next) target = null;
    return changed;
  }

  void finish(int revision, int visiblePage) {
    if (!isCurrent(revision)) return;
    target = null;
    report(visiblePage);
  }

  void cancel() {
    _revision++;
    target = null;
    preview = null;
  }
}

/// Coalesces scrolling updates and serializes writes per comic, including
/// across route replacements. Closing an old chapter queues its last real
/// page before the next chapter can queue a newer write.
class ReaderProgressWriter {
  ReaderProgressWriter({
    required this.comicId,
    required this.save,
    required this.onError,
    this.delay = const Duration(milliseconds: 180),
  });

  final int comicId;
  final Future<void> Function(int page) save;
  final void Function(Object error, StackTrace stack) onError;
  final Duration delay;
  static final Map<int, Future<void>> _tails = {};
  Timer? _timer;
  int? _pending;
  int? _lastQueued;
  bool _closed = false;

  void schedule(int page) {
    if (_closed) return;
    _pending = page;
    _timer?.cancel();
    _timer = Timer(delay, flush);
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final page = _pending;
    _pending = null;
    if (page == null || page == _lastQueued) {
      return _tails[comicId] ?? Future<void>.value();
    }
    _lastQueued = page;
    final previous = _tails[comicId] ?? Future<void>.value();
    late final Future<void> operation;
    operation = previous.then((_) async {
      try {
        await save(page);
      } catch (error, stack) {
        if (_lastQueued == page) _lastQueued = null;
        onError(error, stack);
      }
    }).whenComplete(() {
      if (identical(_tails[comicId], operation)) _tails.remove(comicId);
    });
    _tails[comicId] = operation;
    return operation;
  }

  Future<void> close() {
    _closed = true;
    return flush();
  }
}
