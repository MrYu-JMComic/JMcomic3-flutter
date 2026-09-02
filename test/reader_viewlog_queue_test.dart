import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/reader_viewlog_queue.dart';
import 'package:jmcomic3/reader_viewlog_store.dart';

class _FakeViewlogStore implements ReaderViewlogStore {
  _FakeViewlogStore([Map<String, List<Map<String, dynamic>>>? initial])
      : values = initial ?? <String, List<Map<String, dynamic>>>{};

  final Map<String, List<Map<String, dynamic>>> values;
  int reads = 0;
  int writes = 0;

  @override
  Future<List<Map<String, dynamic>>> read(String key) async {
    reads++;
    return List<Map<String, dynamic>>.from(
      values[key]?.map((event) => Map<String, dynamic>.from(event)) ??
          const <Map<String, dynamic>>[],
    );
  }

  @override
  Future<void> write(String key, List<Map<String, dynamic>> events) async {
    writes++;
    values[key] = events
        .map((event) => Map<String, dynamic>.from(event))
        .toList(growable: false);
  }
}

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

  test('durable queue restores pending events and clears the journal on ack',
      () async {
    final store = _FakeViewlogStore({
      'reader': [
        {
          'page': 7,
          'client_sequence': 4,
          'session_id': 's',
          'comic_id': 1,
          'chapter_id': 2,
        },
      ],
    });
    final delivered = <Map<String, dynamic>>[];
    final q = ReaderViewlogQueue(
      sessionId: 's',
      sink: (event) async => delivered.add(event),
      store: store,
      persistenceKey: 'reader',
      debounce: Duration.zero,
    );

    await q.flush();
    expect(delivered.single['page'], 7);
    expect(q.hasPending, isFalse);
    expect(store.values['reader'], isEmpty);
    expect(store.reads, 1);
    expect(store.writes, 1);
    await q.close();
  });

  test('failed durable event survives a new queue instance', () async {
    final store = _FakeViewlogStore();
    var fail = true;
    final first = ReaderViewlogQueue(
      sessionId: 's',
      sink: (event) async {
        if (fail) {
          throw StateError('offline');
        }
      },
      store: store,
      persistenceKey: 'reader',
      debounce: Duration.zero,
    );
    first.add(page: 3, comicId: 1, chapterId: 2);
    await first.flush();
    expect(first.pendingEvents.single['page'], 3);
    await first.close();
    expect(store.values['reader'], hasLength(1));

    fail = false;
    final delivered = <Map<String, dynamic>>[];
    final second = ReaderViewlogQueue(
      sessionId: 's',
      sink: (event) async => delivered.add(event),
      store: store,
      persistenceKey: 'reader',
      debounce: Duration.zero,
    );
    await second.flush();
    expect(delivered.single['page'], 3);
    expect(store.values['reader'], isEmpty);
    await second.close();
  });

  test('events added while restore is pending receive a later sequence',
      () async {
    final store = _DelayedViewlogStore([
      {
        'page': 1,
        'client_sequence': 9,
        'session_id': 's',
      },
    ]);
    final delivered = <Map<String, dynamic>>[];
    final q = ReaderViewlogQueue(
      sessionId: 's',
      sink: (event) async => delivered.add(event),
      store: store,
      persistenceKey: 'reader',
      debounce: Duration.zero,
    );
    q.add(page: 2);
    store.release();
    await q.flush();

    expect(delivered.map((event) => event['page']), [1, 2]);
    expect(delivered.map((event) => event['client_sequence']), [9, 10]);
    await q.close();
  });
}

class _DelayedViewlogStore implements ReaderViewlogStore {
  _DelayedViewlogStore(this.restored);

  final List<Map<String, dynamic>> restored;
  final Completer<void> _gate = Completer<void>();
  final Map<String, List<Map<String, dynamic>>> values = {};

  void release() => _gate.complete();

  @override
  Future<List<Map<String, dynamic>>> read(String key) async {
    await _gate.future;
    return restored
        .map((event) => Map<String, dynamic>.from(event))
        .toList(growable: false);
  }

  @override
  Future<void> write(String key, List<Map<String, dynamic>> events) async {
    values[key] = events
        .map((event) => Map<String, dynamic>.from(event))
        .toList(growable: false);
  }
}
