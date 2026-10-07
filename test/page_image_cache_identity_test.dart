import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/screens/components/images.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    clearAllImageMemoryCaches();
  });

  test('true-size cache identity includes resolved local path', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'invoke') {
        fail('unexpected method ${call.method}');
      }
      final request = jsonDecode(call.arguments as String) as Map;
      calls++;
      final path = request['params'] as String;
      return jsonEncode({
        'error_message': '',
        'response_data': jsonEncode({
          'w': path.endsWith('a.png') ? 100 : 200,
          'h': path.endsWith('a.png') ? 150 : 300,
        }),
      });
    });

    final first = await cachedPageImageTrueSizeForTest(7, 'p.png', 'a.png');
    final same = await cachedPageImageTrueSizeForTest(7, 'p.png', 'a.png');
    final migrated = await cachedPageImageTrueSizeForTest(7, 'p.png', 'b.png');

    expect(first, const Size(100, 150));
    expect(same, first);
    expect(migrated, const Size(200, 300));
    expect(calls, 2);
  });

  test('invalid image dimensions are rejected and evicted for retry', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      return jsonEncode({
        'error_message': '',
        'response_data': jsonEncode(
          calls == 1 ? {'w': 0, 'h': 200} : {'w': 100, 'h': 200},
        ),
      });
    });

    await expectLater(
      cachedPageImageTrueSizeForTest(8, 'invalid.png', 'invalid.png'),
      throwsA(isA<FormatException>()),
    );
    expect(
      await cachedPageImageTrueSizeForTest(8, 'invalid.png', 'invalid.png'),
      const Size(100, 200),
    );
    expect(calls, 2);
  });
}
