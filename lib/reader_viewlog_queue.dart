import 'dart:async';

class ReaderViewlogQueue {
  ReaderViewlogQueue(
      {required this.sessionId,
      required this.sink,
      this.debounce = const Duration(milliseconds: 250),
      this.maxPending = 256}) {
    if (maxPending <= 0) {
      throw ArgumentError.value(
        maxPending,
        'maxPending',
        'must be greater than zero',
      );
    }
  }
  final String sessionId;
  final Future<void> Function(Map<String, dynamic>) sink;
  final Duration debounce;

  /// Maximum number of unacknowledged events retained in memory. View-log
  /// events are best-effort snapshots; when an offline session outlives this
  /// bound, the oldest snapshots are dropped so a stalled server cannot grow
  /// the reader process without limit. The newest page state is always kept.
  final int maxPending;
  final List<Map<String, dynamic>> _pending = [];
  Timer? _timer;
  int _sequence = 0;
  int _droppedCount = 0;
  bool _closed = false;
  Future<void>? _activeFlush;
  Object? _lastError;

  /// Events that have not been acknowledged by [sink].  The returned maps
  /// are copies so callers can persist/retry them without mutating the queue.
  List<Map<String, dynamic>> get pendingEvents => List.unmodifiable(
        _pending.map((event) => Map<String, dynamic>.from(event)),
      );

  bool get hasPending => _pending.isNotEmpty;

  Object? get lastError => _lastError;

  /// Number of events evicted because [maxPending] was reached. This is a
  /// diagnostic counter, not a server acknowledgement.
  int get droppedCount => _droppedCount;

  int get nextSequence => _sequence + 1;

  void add(
      {required int page,
      double? offset,
      String? mode,
      String? direction,
      int? comicId,
      int? chapterId,
      DateTime? time}) {
    if (_closed) return;
    final event = <String, dynamic>{
      'page': page < 0 ? 0 : page,
      'client_sequence': ++_sequence,
      'session_id': sessionId
    };
    if (offset != null && offset.isFinite && offset >= 0) {
      event['offset'] = offset;
    }
    if (mode != null) event['mode'] = mode;
    if (direction != null) event['direction'] = direction;
    if (comicId != null && comicId > 0) event['comic_id'] = comicId;
    if (chapterId != null && chapterId > 0) event['chapter_id'] = chapterId;
    event['client_time_ms'] =
        (time ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    _retainPending(event);
    _timer?.cancel();
    _timer = Timer(debounce, flush);
  }

  void _retainPending(Map<String, dynamic> event) {
    if (_pending.length >= maxPending) {
      _pending.removeAt(0);
      _droppedCount++;
    }
    _pending.add(event);
  }

  Future<void> flush() async {
    _timer?.cancel();
    if (_activeFlush != null) return _activeFlush!;
    final operation = _flushImpl();
    _activeFlush = operation;
    try {
      await operation;
    } finally {
      _activeFlush = null;
    }
  }

  Future<void> _flushImpl() async {
    // Work through one snapshot.  A failed event is retained for a later
    // explicit retry, while later events still get a chance to reach the
    // server.  Retrying a permanently failing event in the same call would
    // create a tight loop during dispose/offline operation.
    while (_pending.isNotEmpty) {
      final batch = List<Map<String, dynamic>>.from(_pending);
      _pending.clear();
      var failed = false;
      for (final event in batch) {
        try {
          await sink(Map<String, dynamic>.unmodifiable(event));
          _lastError = null;
        } catch (error) {
          failed = true;
          _lastError = error;
          _retainPending(event);
        }
      }
      // New events may have been queued by a sink callback. Sequence order is
      // the only stable ordering across retries and concurrent additions.
      _pending.sort((a, b) =>
          (a['client_sequence'] as int).compareTo(b['client_sequence'] as int));
      if (failed) {
        return;
      }
      // If the sink queued more events while acknowledging this batch, loop
      // once more. Otherwise this exits immediately.
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    await flush();
  }
}
