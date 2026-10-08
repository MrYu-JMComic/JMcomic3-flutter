import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/screens/reader/reader_position.dart';

void main() {
  test('jump target and preview never become persisted visible progress', () {
    final position = ReaderPosition(10, 0);
    final first = position.request(8);
    position.report(2);
    expect(position.current, 2);
    expect(position.displayPage, 8);
    final latest = position.request(4);
    position.finish(first, 8);
    expect(position.current, 2);
    expect(position.displayPage, 4);
    position.finish(latest, 4);
    expect(position.current, 4);
    expect(position.displayPage, 4);
    expect(position.target, isNull);
    position.preview = 7;
    expect(position.current, 4);
    position.cancel();
    expect(position.displayPage, 4);
  });

  test('rapid controls accumulate from intent and indices stay in range', () {
    final position = ReaderPosition(5, 100);
    expect(position.current, 4);
    position.request(-10);
    expect(position.navigationPage, 0);
    position.request(position.navigationPage + 1);
    position.request(position.navigationPage + 1);
    expect(position.navigationPage, 2);
    expect(position.current, 4);
    position.report(100);
    expect(position.current, 4);
  });

  test('progress writer coalesces pending pages and closes without timers',
      () async {
    final saved = <int>[];
    final writer = ReaderProgressWriter(
        comicId: 1,
        save: (page) async => saved.add(page),
        onError: (e, s) => fail('$e'));
    for (var page = 0; page < 8; page++) {
      writer.schedule(page);
    }
    await writer.close();
    writer.schedule(9);
    expect(saved, [7]);
  });

  test('old chapter write finishes before new chapter for the same comic',
      () async {
    final gate = Completer<void>();
    final saved = <String>[];
    final old = ReaderProgressWriter(
        comicId: 2,
        save: (page) async {
          await gate.future;
          saved.add('old:$page');
        },
        onError: (e, s) => fail('$e'));
    final next = ReaderProgressWriter(
        comicId: 2,
        save: (page) async => saved.add('new:$page'),
        onError: (e, s) => fail('$e'));
    old.schedule(4);
    final closing = old.close();
    next.schedule(0);
    final opening = next.flush();
    await Future<void>.delayed(Duration.zero);
    expect(saved, isEmpty);
    gate.complete();
    await Future.wait([closing, opening]);
    expect(saved, ['old:4', 'new:0']);
    await next.close();
  });

  test('failed save does not poison later progress writes', () async {
    var attempts = 0;
    final errors = <Object>[];
    final writer = ReaderProgressWriter(
        comicId: 3,
        save: (_) async {
          if (++attempts == 1) throw StateError('fixture');
        },
        onError: (error, _) => errors.add(error));
    writer.schedule(1);
    await writer.flush();
    writer.schedule(2);
    await writer.close();
    expect(attempts, 2);
    expect(errors, hasLength(1));
  });
}
