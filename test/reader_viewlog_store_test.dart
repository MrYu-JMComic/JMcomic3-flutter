import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/reader_viewlog_store.dart';

const _methodsChannel = MethodChannel('methods');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_methodsChannel, null);
  });

  test('property keys reject malformed session ids', () {
    expect(
      ReaderViewlogPropertyStore.keyForSession('reader-1:2'),
      'reader_viewlog_v1:reader-1:2',
    );
    expect(
      () => ReaderViewlogPropertyStore.keyForSession('reader/1'),
      throwsArgumentError,
    );
    expect(
      () => ReaderViewlogPropertyStore.keyForSession(' '),
      throwsArgumentError,
    );
  });

  test('property store round trips a versioned journal', () async {
    final values = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_methodsChannel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      final method = request['method'];
      if (method == 'load_property') {
        return jsonEncode({
          'error_message': '',
          'response_data': values[request['params']] ?? '',
        });
      }
      if (method == 'save_property') {
        final params = jsonDecode(request['params'] as String) as Map;
        values[params['k'] as String] = params['v'] as String;
        return jsonEncode({'error_message': '', 'response_data': ''});
      }
      fail('unexpected method $method');
    });

    final store = ReaderViewlogPropertyStore();
    const key = 'reader_viewlog_v1:reader-1-2';
    await store.write(key, [
      {
        'page': 4,
        'client_sequence': 1,
        'session_id': 'reader-1-2',
        'comic_id': 1,
        'chapter_id': 2,
      },
    ]);
    final restored = await store.read(key);
    expect(restored.single['page'], 4);
    expect(restored.single['session_id'], 'reader-1-2');

    values[key] = '{"version":99,"events":[]}';
    await expectLater(store.read(key), throwsFormatException);
  });

  test('property store keeps newest events under count and byte limits',
      () async {
    final values = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_methodsChannel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      if (request['method'] == 'save_property') {
        final params = jsonDecode(request['params'] as String) as Map;
        values[params['k'] as String] = params['v'] as String;
      }
      return jsonEncode({'error_message': '', 'response_data': ''});
    });

    final store = ReaderViewlogPropertyStore();
    const key = 'reader_viewlog_v1:reader-1-2';
    await store.write(
      key,
      List.generate(
        ReaderViewlogPropertyStore.maxEvents + 20,
        (index) => {
          'page': index,
          'client_sequence': index + 1,
          'session_id': 'reader-1-2',
          'mode': 'x' * 400,
        },
      ),
    );
    final encoded = values[key]!;
    expect(utf8.encode(encoded).length,
        lessThanOrEqualTo(ReaderViewlogPropertyStore.maxEncodedBytes));
    final decoded = jsonDecode(encoded) as Map;
    final events = decoded['events'] as List;
    expect(
        events.length, lessThanOrEqualTo(ReaderViewlogPropertyStore.maxEvents));
    expect((events.last as Map)['page'],
        ReaderViewlogPropertyStore.maxEvents + 19);
  });
}
