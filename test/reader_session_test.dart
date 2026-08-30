import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/reader_session.dart';

void main() {
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
    final first = scheduler.schedule(session.current, () async => throw StateError('x'), key: 'p');
    final second = scheduler.schedule(session.current, () async => 2, key: 'p');
    expect(identical(first, second), isTrue);
    expect((await first.future).outcome, PrefetchOutcome.failed);
    scheduler.close();
  });
}
