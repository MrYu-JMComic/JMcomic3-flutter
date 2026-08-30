import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/reader_viewlog_queue.dart';

void main() {
  test('sequences events and preserves legacy page field', () async {
    final events = <Map<String, dynamic>>[];
    final q =
        ReaderViewlogQueue(sessionId: 's', sink: (e) async => events.add(e));
    q.add(page: 2, offset: 10, mode: 'single');
    await q.flush();
    expect(events.single['page'], 2);
    expect(events.single['client_sequence'], 1);
    expect(events.single['session_id'], 's');
    expect(events.single['offset'], 10);
    expect(events.single['client_time_ms'], isA<int>());
  });

  test(
      'sink failure does not stop subsequent events and close rejects new ones',
      () async {
    var calls = 0;
    final q = ReaderViewlogQueue(
        sessionId: 's',
        sink: (_) async {
          calls++;
          if (calls == 1) throw StateError('x');
        });
    q.add(page: 1);
    q.add(page: 2);
    await q.flush();
    expect(calls, 2);
    // The failed event is retained instead of being silently lost.
    expect(q.pendingEvents.map((e) => e['page']), [1]);
    await q.flush();
    expect(calls, 3);
    expect(q.hasPending, isFalse);
    await q.close();
    q.add(page: 3);
    await q.flush();
    expect(calls, 3);
  });

  test('permanent sink failure is bounded and remains retryable', () async {
    var calls = 0;
    final q = ReaderViewlogQueue(
      sessionId: 's',
      sink: (_) async {
        calls++;
        throw StateError('offline');
      },
    );
    q.add(page: 1, comicId: 7, chapterId: 8);
    await q.flush();
    await q.flush();
    expect(calls, 2);
    expect(q.pendingEvents.single['comic_id'], 7);
    expect(q.pendingEvents.single['chapter_id'], 8);
    expect(q.lastError, isA<StateError>());
    await q.close();
    expect(calls, 3);
    expect(q.hasPending, isTrue);
  });

  test('concurrent flushes share completion and sanitize values', () async {
    final events = <Map<String, dynamic>>[];
    final q = ReaderViewlogQueue(
        sessionId: 's',
        sink: (e) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          events.add(e);
        });
    q.add(page: -1, offset: double.nan);
    await Future.wait([q.flush(), q.flush()]);
    expect(events.single['page'], 0);
    expect(events.single.containsKey('offset'), isFalse);
  });

  test('pending view-log memory is bounded and drops oldest snapshots',
      () async {
    expect(
      () => ReaderViewlogQueue(
        sessionId: 's',
        sink: (_) async {},
        maxPending: 0,
      ),
      throwsArgumentError,
    );
    final q = ReaderViewlogQueue(
      sessionId: 's',
      sink: (_) async => throw StateError('offline'),
      maxPending: 2,
      debounce: const Duration(days: 1),
    );
    q.add(page: 1);
    q.add(page: 2);
    q.add(page: 3);

    expect(q.pendingEvents.map((event) => event['page']), [2, 3]);
    expect(q.droppedCount, 1);
    await q.close();
    expect(q.pendingEvents.map((event) => event['page']), [2, 3]);
  });
}
