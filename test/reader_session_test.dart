import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/reader_session.dart';

void main() {
  test('scheduler rejects an invalid concurrency budget', () {
    expect(() => PrefetchScheduler(maxConcurrent: 0), throwsArgumentError);
  });

  test('generation changes when chapter changes or closes', () {
    final session = ReaderSession();
    final first = session.openChapter(const ChapterIdentity('a'));
    expect(session.isCurrent(first), isTrue);
    final second = session.openChapter(const ChapterIdentity('b'));
    expect(session.isCurrent(first), isFalse);
    expect(session.isCurrent(second), isTrue);
    session.close();
    expect(session.isCurrent(second), isFalse);
  });

  test('scheduler distinguishes cancellation and stale result', () async {
    final session = ReaderSession();
    final generation = session.openChapter(const ChapterIdentity('a'));
    final scheduler = PrefetchScheduler();
    final cancelled = scheduler.schedule(generation, () async => 1);
    cancelled.cancel();
    expect((await cancelled.future).outcome, PrefetchOutcome.cancelled);

    final stale = scheduler.schedule(generation, () async => 2,
        isCurrent: () => session.isCurrent(generation));
    session.openChapter(const ChapterIdentity('b'));
    expect((await stale.future).outcome, PrefetchOutcome.discarded);
    scheduler.close();
  });

  test('scheduler reports failures and deduplicates keys', () async {
    final session = ReaderSession()..openChapter(const ChapterIdentity('a'));
    final scheduler = PrefetchScheduler();
    final first = scheduler
        .schedule(session.current, () async => throw StateError('x'), key: 'p');
    final second = scheduler.schedule(session.current, () async => 2, key: 'p');
    expect(identical(first, second), isTrue);
    expect((await first.future).outcome, PrefetchOutcome.failed);
    final again = scheduler.schedule(session.current, () async => 3, key: 'p');
    expect(identical(first, again), isFalse);
    expect((await again.future).value, 3);
    scheduler.close();
  });

  test('higher priority queued work runs first', () async {
    final session = ReaderSession()..openChapter(const ChapterIdentity('a'));
    final scheduler = PrefetchScheduler(maxConcurrent: 1);
    var release = false;
    final first = scheduler.schedule(session.current, () async {
      while (!release) {
        await Future<void>.delayed(Duration.zero);
      }
      return 1;
    }, priority: 0);
    final order = <int>[];
    final low = scheduler.schedule(session.current, () async {
      order.add(1);
      return 1;
    }, priority: 1);
    final high = scheduler.schedule(session.current, () async {
      order.add(2);
      return 2;
    }, priority: 5);
    release = true;
    await first.future;
    await Future.wait([low.future, high.future]);
    expect(order, [2, 1]);
    scheduler.close();
  });

  test('close cancels running result and rejects new work', () async {
    final session = ReaderSession()..openChapter(const ChapterIdentity('a'));
    final scheduler = PrefetchScheduler(maxConcurrent: 1);
    final gate = Completer<void>();
    final running = scheduler.schedule(session.current, () async {
      await gate.future;
      return 7;
    }, key: 'running');
    // Let the scheduler start the loader before closing it.
    await Future<void>.delayed(Duration.zero);
    scheduler.close();
    expect((await running.future).outcome, PrefetchOutcome.cancelled);
    final after =
        scheduler.schedule(session.current, () async => 8, key: 'after');
    expect((await after.future).outcome, PrefetchOutcome.cancelled);
    gate.complete();
  });

  test('generation cancellation releases dedupe key for the new chapter',
      () async {
    final session = ReaderSession();
    final firstGeneration = session.openChapter(const ChapterIdentity('a'));
    final scheduler = PrefetchScheduler(maxConcurrent: 1);
    final gate = Completer<void>();
    var oldRuns = 0;
    var newRuns = 0;
    final old = scheduler.schedule(firstGeneration, () async {
      oldRuns++;
      await gate.future;
      return 1;
    }, key: 'same-page');
    await Future<void>.delayed(Duration.zero);

    final secondGeneration = session.openChapter(const ChapterIdentity('b'));
    scheduler.cancelGeneration(firstGeneration);
    final replacement = scheduler.schedule(secondGeneration, () async {
      newRuns++;
      return 2;
    }, isCurrent: () => session.isCurrent(secondGeneration), key: 'same-page');

    expect(identical(old, replacement), isFalse);
    expect((await old.future).outcome, PrefetchOutcome.cancelled);
    // The old underlying loader is not force-cancellable; release its I/O
    // budget before waiting for the replacement to run.
    gate.complete();
    expect((await replacement.future).value, 2);
    expect(oldRuns, 1);
    expect(newRuns, 1);
    scheduler.close();
  });

  test('same dedupe key is isolated across live generations', () async {
    final session = ReaderSession();
    final first = session.openChapter(const ChapterIdentity('a'));
    final scheduler = PrefetchScheduler(maxConcurrent: 2);
    final gate = Completer<void>();
    final old = scheduler.schedule(first, () async {
      await gate.future;
      return 1;
    }, isCurrent: () => session.isCurrent(first), key: 'page');
    await Future<void>.delayed(Duration.zero);
    final second = session.openChapter(const ChapterIdentity('b'));
    final fresh = scheduler.schedule(second, () async => 2, key: 'page');
    expect(identical(old, fresh), isFalse);
    gate.complete();
    expect((await old.future).outcome, PrefetchOutcome.discarded);
    expect((await fresh.future).value, 2);
    scheduler.close();
  });

  test('generation cancellation also stops unkeyed active work', () async {
    final session = ReaderSession();
    final first = session.openChapter(const ChapterIdentity('a'));
    final scheduler = PrefetchScheduler(maxConcurrent: 1);
    final gate = Completer<void>();
    final running = scheduler.schedule(first, () async {
      await gate.future;
      return 9;
    }, isCurrent: () => session.isCurrent(first));
    await Future<void>.delayed(Duration.zero);

    session.openChapter(const ChapterIdentity('b'));
    scheduler.cancelGeneration(first);
    expect((await running.future).outcome, PrefetchOutcome.cancelled);

    // A running loader cannot be force-cancelled by Dart; release it so the
    // scheduler's concurrency slot is eventually returned.
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    scheduler.close();
  });

  test('generation cancellation removes same-generation dedupe handles',
      () async {
    final session = ReaderSession();
    final generation = session.openChapter(const ChapterIdentity('a'));
    final scheduler = PrefetchScheduler(maxConcurrent: 1);
    final gate = Completer<void>();
    final old = scheduler.schedule(generation, () async {
      await gate.future;
      return 1;
    }, key: 'page');
    await Future<void>.delayed(Duration.zero);

    scheduler.cancelGeneration(generation);
    final retry = scheduler.schedule(generation, () async => 2, key: 'page');
    expect(identical(old, retry), isFalse);
    expect((await old.future).outcome, PrefetchOutcome.cancelled);
    gate.complete();
    expect((await retry.future).value, 2);
    scheduler.close();
  });

  test('stale queued work is discarded without invoking its loader', () async {
    final session = ReaderSession();
    final first = session.openChapter(const ChapterIdentity('a'));
    final scheduler = PrefetchScheduler(maxConcurrent: 1);
    final gate = Completer<void>();
    final running = scheduler.schedule(first, () async {
      await gate.future;
      return 1;
    });
    var staleRuns = 0;
    final stale = scheduler.schedule(first, () async {
      staleRuns++;
      return 2;
    }, isCurrent: () => session.isCurrent(first));
    session.openChapter(const ChapterIdentity('b'));
    gate.complete();
    await running.future;
    expect((await stale.future).outcome, PrefetchOutcome.discarded);
    expect(staleRuns, 0);
    scheduler.close();
  });
}
