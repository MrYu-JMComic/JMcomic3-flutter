import 'dart:async';

/// Lightweight reader orchestration primitives.
///
/// This file is intentionally UI and transport agnostic.  It can be adopted by
/// a screen incrementally; no reader widget depends on it today.

class ChapterIdentity {
  final String value;
  const ChapterIdentity(this.value);

  @override
  bool operator ==(Object other) =>
      other is ChapterIdentity && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

class ReaderGeneration {
  final ChapterIdentity chapter;
  final int value;
  const ReaderGeneration(this.chapter, this.value);

  @override
  bool operator ==(Object other) =>
      other is ReaderGeneration &&
      other.value == value &&
      other.chapter == chapter;

  @override
  int get hashCode => Object.hash(chapter, value);
}

enum PrefetchOutcome { completed, cancelled, discarded, failed }

class PrefetchResult<T> {
  final PrefetchOutcome outcome;
  final T? value;
  final Object? error;
  const PrefetchResult._(this.outcome, this.value, this.error);
  const PrefetchResult.completed(T value)
      : this._(PrefetchOutcome.completed, value, null);
  const PrefetchResult.cancelled()
      : this._(PrefetchOutcome.cancelled, null, null);
  const PrefetchResult.discarded()
      : this._(PrefetchOutcome.discarded, null, null);
  const PrefetchResult.failed(Object error)
      : this._(PrefetchOutcome.failed, null, error);
}

/// Owns the active chapter and monotonically increasing generation token.
class ReaderSession {
  ChapterIdentity? _chapter;
  int _generation = 0;

  ReaderGeneration openChapter(ChapterIdentity chapter) {
    _chapter = chapter;
    return ReaderGeneration(chapter, ++_generation);
  }

  ReaderGeneration get current => ReaderGeneration(
        _chapter ?? (throw StateError('No chapter is open')),
        _generation,
      );

  bool isCurrent(ReaderGeneration generation) =>
      generation.value == _generation && generation.chapter == _chapter;

  void close() {
    _chapter = null;
    _generation++;
  }
}

typedef PrefetchLoader<T> = Future<T> Function();

class PrefetchHandle<T> {
  final ReaderGeneration generation;
  final Future<PrefetchResult<T>> future;
  final void Function() cancel;
  PrefetchHandle(this.generation, this.future, this.cancel);
}

/// Small, bounded-concurrency scheduler. Cancellation is represented in the
/// result; a completed load from an old generation is represented as discarded.
class PrefetchScheduler {
  final int maxConcurrent;
  int _running = 0;
  final List<_Job<dynamic>> _pending = [];
  final Set<_Job<dynamic>> _activeJobs = <_Job<dynamic>>{};
  final Map<Object, PrefetchHandle<dynamic>> _dedupe = {};
  bool _closed = false;

  PrefetchScheduler({this.maxConcurrent = 2}) {
    if (maxConcurrent <= 0) {
      throw ArgumentError.value(maxConcurrent, 'maxConcurrent', 'must be > 0');
    }
  }

  PrefetchHandle<T> schedule<T>(
      ReaderGeneration generation, PrefetchLoader<T> loader,
      {bool Function()? isCurrent, int priority = 0, Object? key}) {
    if (_closed) {
      return PrefetchHandle<T>(
        generation,
        Future<PrefetchResult<T>>.value(const PrefetchResult.cancelled()),
        () {},
      );
    }
    final dedupeKey = key == null ? null : _PrefetchDedupeKey(generation, key);
    if (dedupeKey != null) {
      final existing = _dedupe[dedupeKey];
      if (existing != null) return existing as PrefetchHandle<T>;
    }
    late final _Job<T> job;
    late final PrefetchHandle<T> handle;
    final completer = Future<PrefetchResult<T>>.sync(() {
      job = _Job<T>(generation, loader, isCurrent, priority);
      _pending.add(job);
      _pending.sort((a, b) => b.priority.compareTo(a.priority));
      _pump();
      return job.future;
    }).then((value) => value);
    void cancel() {
      job.cancelAndComplete();
      if (dedupeKey != null && identical(_dedupe[dedupeKey], handle)) {
        _dedupe.remove(dedupeKey);
      }
      _pump();
    }

    handle = PrefetchHandle(generation, completer, cancel);
    if (dedupeKey != null) _dedupe[dedupeKey] = handle;
    final cleanup = completer.whenComplete(() {
      if (dedupeKey != null && identical(_dedupe[dedupeKey], handle)) {
        _dedupe.remove(dedupeKey);
      }
    });
    // The public future is intentionally value-based and should not reject,
    // but keep the bookkeeping branch typed as `void` so an unexpected error
    // cannot become an unhandled asynchronous error or analyzer warning.
    unawaited(cleanup.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    ));
    return handle;
  }

  void _pump() {
    if (_closed) return;
    while (_running < maxConcurrent && _pending.isNotEmpty) {
      final job = _pending.removeAt(0);
      if (job.cancelled) {
        job.cancelAndComplete();
        continue;
      }
      if (job.isCurrent != null && !job.isCurrent!()) {
        job.discardAndComplete();
        continue;
      }
      _running++;
      _activeJobs.add(job);
      job.run().whenComplete(() {
        _running--;
        _activeJobs.remove(job);
        _pump();
      });
    }
  }

  void close() {
    _closed = true;
    for (final job in _pending) {
      job.cancelAndComplete();
    }
    _pending.clear();
    for (final job in _activeJobs) {
      // Complete the public Future immediately; the underlying loader may
      // still finish later because Dart futures cannot be force-cancelled.
      job.cancelAndComplete();
    }
    _dedupe.clear();
  }

  /// Cancels queued and in-flight work belonging to an old reader generation.
  /// The underlying transport may not support hard cancellation, so running
  /// loaders still consume whatever I/O they already started; their result is
  /// explicitly reported as [PrefetchOutcome.cancelled] and cannot publish.
  void cancelGeneration(ReaderGeneration generation) {
    for (final job in List<_Job<dynamic>>.of(_pending)) {
      if (job.generation == generation) {
        job.cancelAndComplete();
      }
    }
    // Dedupe handles cover the common reader path, but callers are allowed to
    // schedule a job without a key.  Walk active jobs directly as well so a
    // generation switch never leaves an unkeyed request running as if it were
    // still current.
    for (final job in List<_Job<dynamic>>.of(_activeJobs)) {
      if (job.generation == generation) {
        job.cancelAndComplete();
      }
    }
    // Remove handles immediately, rather than waiting for an in-flight loader
    // to settle.  Otherwise a same-generation retry issued in the small
    // cancellation window could receive an already-cancelled handle.
    _dedupe.removeWhere(
      (key, _) => key is _PrefetchDedupeKey && key.generation == generation,
    );
    _pump();
  }
}

class _PrefetchDedupeKey {
  const _PrefetchDedupeKey(this.generation, this.key);
  final ReaderGeneration generation;
  final Object key;

  @override
  bool operator ==(Object other) =>
      other is _PrefetchDedupeKey &&
      other.generation == generation &&
      other.key == key;

  @override
  int get hashCode => Object.hash(generation.chapter, generation.value, key);
}

class _Job<T> {
  final ReaderGeneration generation;
  final PrefetchLoader<T> loader;
  final bool Function()? isCurrent;
  final int priority;
  final _completer = Completer<PrefetchResult<T>>();
  bool _cancelled = false;
  _Job(this.generation, this.loader, this.isCurrent, this.priority);
  Future<PrefetchResult<T>> get future => _completer.future;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
  void cancelAndComplete() {
    _cancelled = true;
    complete(PrefetchResult<T>.cancelled());
  }

  void discardAndComplete() {
    complete(PrefetchResult<T>.discarded());
  }

  void complete(PrefetchResult<T> result) {
    if (!_completer.isCompleted) _completer.complete(result);
  }

  Future<void> run() async {
    try {
      final value = await loader();
      complete(cancelled
          ? const PrefetchResult.cancelled()
          : (isCurrent != null && !isCurrent!()
              ? const PrefetchResult.discarded()
              : PrefetchResult.completed(value)));
    } catch (error) {
      complete(cancelled
          ? const PrefetchResult.cancelled()
          : PrefetchResult.failed(error));
    }
  }
}
