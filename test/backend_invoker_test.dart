import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/backend_invoker.dart';
import 'package:jmcomic3/basic/methods.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');

  setUp(() {
    BackendInvokerRegistry.reset();
  });

  tearDown(() {
    BackendInvokerRegistry.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('injected backend receives calls before the legacy channel', () async {
    final calls = <Map<String, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          fail(
            'legacy MethodChannel should not be used while a backend is installed',
          );
        });
    BackendInvokerRegistry.install((method, params) async {
      calls.add({'method': method, 'params': params});
      return jsonEncode({
        'error_message': '',
        'response_data': method == 'load_property' ? 'injected-value' : '',
      });
    });

    expect(await methods.loadProperty('example'), 'injected-value');
    expect(calls, [
      {'method': 'load_property', 'params': 'example'},
    ]);
  });

  test('reset restores the legacy MethodChannel backend', () async {
    var channelCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          channelCalls++;
          return jsonEncode({'error_message': '', 'response_data': 'legacy'});
        });
    BackendInvokerRegistry.install(
      (_, __) async =>
          jsonEncode({'error_message': '', 'response_data': 'injected'}),
    );
    BackendInvokerRegistry.reset();

    expect(await methods.loadProperty('example'), 'legacy');
    expect(channelCalls, 1);
  });

  test(
    'download object fallback retries only an invalid-params response',
    () async {
      final paramsSeen = <dynamic>[];
      BackendInvokerRegistry.install((method, params) async {
        expect(method, 'dl_image_by_chapter_id');
        paramsSeen.add(params);
        if (params is Map) {
          return jsonEncode({
            'error_message': 'dl_image_by_chapter_id invalid params',
            'response_data': '',
          });
        }
        return jsonEncode({
          'error_message': '',
          'response_data': jsonEncode([
            {
              'album_id': 2,
              'chapter_id': 10,
              'image_index': 0,
              'name': '001.jpg',
              'key': '10_0',
              'dl_status': 0,
              'width': 0,
              'height': 0,
            },
          ]),
        });
      });

      final result = await methods.dlImageByChapterId(10, albumId: 2);
      expect(result.single.albumId, 2);
      expect(paramsSeen, [
        {'chapter_id': 10, 'album_id': 2},
        '10',
      ]);
    },
  );

  test(
    'business errors are not mistaken for protocol incompatibility',
    () async {
      var calls = 0;
      BackendInvokerRegistry.install((_, __) async {
        calls++;
        return jsonEncode({
          'error_message': 'invalid credentials',
          'response_data': '',
        });
      });

      await expectLater(
        methods.dlImageByChapterId(10, albumId: 2),
        throwsA(isA<StateError>()),
      );
      expect(calls, 1);
    },
  );
}
