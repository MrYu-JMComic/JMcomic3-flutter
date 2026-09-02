import 'dart:async';

import 'reader_viewlog_store.dart';

class ReaderViewlogQueue {
  ReaderViewlogQueue(
      {required this.sessionId,
      required this.sink,
      this.debounce = const Duration(milliseconds: 250),
      this.maxPending = 256,
      this.store,
      this.persistenceKey}) {
    if (maxPending <= 0) {
      throw ArgumentError.value(
        maxPending,
        'maxPending',
        'must be greater than zero',
      );
    }
    if (store != null &&
        (persistenceKey == null || persistenceKey!.trim().isEmpty)) {
      throw ArgumentError.value(
        persistenceKey,
        'persistenceKey',
        'is required when a store is provided',
      );
    }
    if (store != null) {
      _restoreFuture = _restorePending();
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
  final ReaderViewlogStore? store;
  final String? persistenceKey;
  final List<Map<String, dynamic>> _pending = [];
  Timer? _timer;
  Timer? _persistTimer;
  int _sequence = 0;
  int _droppedCount = 0;
  bool _closed = false;
  Future<void>? _activeFlush;
  Future<void>? _restoreFuture;
  Future<void>? _activePersist;
  bool _persistRequested = false;
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
    _requestPersist();
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

  Future<void> _restorePending() async {
    final store = this.store;
    final key = persistenceKey;
    if (store == null || key == null) {
      return;
    }
    try {
      final restored = await store.read(key);
      final retained = restored
          .where((event) => event['session_id'] == sessionId)
          .map((event) => Map<String, dynamic>.from(event))
          .toList(growable: false);
      final early = List<Map<String, dynamic>>.from(_pending);
      _pending.clear();
      retained.sort(_compareSequence);
      for (final event in retained) {
        final sequence = event['client_sequence'];
        if (sequence is int && sequence > _sequence) {
          _sequence = sequence;
        }
        _retainPending(event);
      }
      // Events added while the store was being read must follow the durable
      // sequence range. Rebase only those local events, preserving order.
      early.sort(_compareSequence);
      for (final event in early) {
        final rebased = Map<String, dynamic>.from(event)
          ..['client_sequence'] = ++_sequence;
        _retainPending(rebased);
      }
      _pending.sort(_compareSequence);
    } catch (error) {
      // A corrupt/unavailable journal must not stop the reader. Keep new
      // in-memory events and surface only the error type to diagnostics.
      _lastError = error;
    }
  }

  static int _compareSequence(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final left = a['client_sequence'];
    final right = b['client_sequence'];
    if (left is int && right is int) {
      return left.compareTo(right);
    }
    return 0;
  }

  void _requestPersist({bool immediate = false}) {
    if (store == null || persistenceKey == null) {
      return;
    }
    _persistRequested = true;
    if (immediate) {
      _persistTimer?.cancel();
      _persistTimer = null;
      unawaited(_persistNow());
      return;
    }
    _persistTimer ??= Timer(const Duration(milliseconds: 250), () {
      _persistTimer = null;
      unawaited(_persistNow());
    });
  }

  Future<void> _persistNow() {
    _persistTimer?.cancel();
    _persistTimer = null;
    final active = _activePersist;
    if (active != null) {
      return active;
    }
    final operation = _persistImpl();
    _activePersist = operation;
    return operation.whenComplete(() {
      if (identical(_activePersist, operation)) {
        _activePersist = null;
      }
    });
  }

  Future<void> _persistImpl() async {
    final store = this.store;
    final key = persistenceKey;
    if (store == null || key == null) {
      return;
    }
    final restore = _restoreFuture;
    if (restore != null) {
      await restore;
    }
    while (_persistRequested) {
      _persistRequested = false;
      try {
        await store.write(key, pendingEvents);
        _lastError = null;
      } catch (error) {
        // Do not spin on a permanently unavailable backend. The next event or
        // an explicit close/flush will request another bounded attempt.
        _lastError = error;
        return;
      }
    }
  }

  Future<void> _awaitPersistence() async {
    if (store == null || persistenceKey == null) {
      return;
    }
    if (_persistRequested) {
      await _persistNow();
      return;
    }
    final active = _activePersist;
    if (active != null) {
      await active;
    }
  }

  Future<void> flush() async {
    _timer?.cancel();
    final restore = _restoreFuture;
    if (restore != null) {
      await restore;
    }
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
      _requestPersist();
      if (failed) {
        await _awaitPersistence();
        return;
      }
      // If the sink queued more events while acknowledging this batch, loop
      // once more. Otherwise this exits immediately.
    }
    await _awaitPersistence();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _persistTimer?.cancel();
    _persistTimer = null;
    final restore = _restoreFuture;
    if (restore != null) {
      await restore;
    }
    await flush();
    await _awaitPersistence();
  }
}
