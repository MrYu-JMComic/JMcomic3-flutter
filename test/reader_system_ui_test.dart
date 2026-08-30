import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/reader_system_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('release platform restore waits for an in-flight enter command',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <SystemUiMode>[];
    final firstStarted = Completer<void>();
    final allowFirst = Completer<void>();
    var systemUiCalls = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIMode' ||
          call.method == 'SystemChrome.setEnabledSystemUIOverlays') {
        final mode = call.method == 'SystemChrome.setEnabledSystemUIOverlays'
            ? SystemUiMode.manual
            : SystemUiMode.edgeToEdge;
        calls.add(mode);
        systemUiCalls++;
        if (systemUiCalls == 1) {
          firstStarted.complete();
          await allowFirst.future;
        }
      }
      return null;
    });

    ReaderSystemUiLease? lease;
    try {
      lease = enterReaderSystemUi(fullScreen: true);
      await firstStarted.future;
      final release = lease.release();

      // The restore is queued behind the pending enter, not sent out of
      // order while the first platform call is still blocked.
      await Future<void>.delayed(Duration.zero);
      expect(calls, [SystemUiMode.manual]);

      allowFirst.complete();
      await release;
      expect(calls, [SystemUiMode.manual, SystemUiMode.edgeToEdge]);
    } finally {
      if (!allowFirst.isCompleted) allowFirst.complete();
      if (lease != null) await lease.release();
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    }
  });
}
