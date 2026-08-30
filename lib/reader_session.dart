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
}

enum PrefetchOutcome { completed, cancelled, discarded }

class PrefetchResult<T> {
  final PrefetchOutcome outcome;
  final T? value;
  final Object? error;
  const PrefetchResult._(this.outcome, this.value, this.error);
  const PrefetchResult.completed(T value)
      : this._(PrefetchOutcome.completed, value, null);
  const PrefetchResult.cancelled() : this._(PrefetchOutcome.cancelled, null, null);
  const PrefetchResult.discarded() : this._(PrefetchOutcome.discarded, null, null);
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
  bool _closed = false;

  PrefetchScheduler({this.maxConcurrent = 2})
      : assert(maxConcurrent > 0);

  PrefetchHandle<T> schedule<T>(
      ReaderGeneration generation, PrefetchLoader<T> loader,
      {bool Function()? isCurrent}) {
    var cancelled = false;
    final completer = Future<PrefetchResult<T>>.sync(() {
      final job = _Job<T>(generation, loader, () => cancelled, isCurrent);
      _pending.add(job);
      _pump();
      return job.future;
    }).then((value) => value);
    void cancel() {
      cancelled = true;
      _pump();
    }
    return PrefetchHandle(generation, completer, cancel);
  }

  void _pump() {
    if (_closed) return;
    while (_running < maxConcurrent && _pending.isNotEmpty) {
      final job = _pending.removeAt(0);
      if (job.cancelled) {
        job.complete(const PrefetchResult.cancelled());
        continue;
      }
      _running++;
      job.run().whenComplete(() {
        _running--;
        _pump();
      });
    }
  }

  void close() {
    _closed = true;
    for (final job in _pending) {
      job.complete(const PrefetchResult.cancelled());
    }
    _pending.clear();
  }
}

class _Job<T> {
  final ReaderGeneration generation;
  final PrefetchLoader<T> loader;
  final bool Function() _isCancelled;
  final bool Function()? isCurrent;
  final _completer = Completer<PrefetchResult<T>>();
  _Job(this.generation, this.loader, this._isCancelled, this.isCurrent);
  Future<PrefetchResult<T>> get future => _completer.future;
  bool get cancelled => _isCancelled();
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
      complete(PrefetchResult._(PrefetchOutcome.completed, null, error));
    }
  }
}
