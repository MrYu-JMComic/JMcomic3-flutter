import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/methods.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  Map<String, dynamic> requestOf(MethodCall call) =>
      jsonDecode(call.arguments as String) as Map<String, dynamic>;
  String envelope(String responseData, {String errorMessage = ''}) =>
      jsonEncode(
          {'error_message': errorMessage, 'response_data': responseData});
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('disabled switch falls back to single page', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'invoke');
      final request = requestOf(call);
      calls.add(request['method'] as String);
      if (request['method'] == 'jm_page_image') {
        return envelope('/safe/p.jpg');
      }
      return envelope('');
    });
    final result =
        await methods.jmPageImageBatch([const JmPageImageRequest(1, 'p.jpg')]);
    expect(result.single.path, '/safe/p.jpg');
    expect(calls, ['jm_page_image']);
  });

  test('batch preserves duplicate ids and chunks at sixteen', () async {
    var batches = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'invoke');
      final request = requestOf(call);
      if (request['method'] == 'jm_page_image_batch') {
        batches++;
        final params =
            jsonDecode(request['params'] as String) as Map<String, dynamic>;
        final pages = params['pages'] as List;
        return envelope(jsonEncode({
          'version': 1,
          'items': pages.map((p) => {'id': p['id'], 'path': '/x'}).toList(),
        }));
      }
      fail('unexpected single fallback');
    });
    final pages = List.generate(
        17, (i) => JmPageImageRequest(i == 16 ? 1 : i + 1, '$i.jpg'));
    final result = await methods.jmPageImageBatch(pages, enabled: true);
    expect(result, hasLength(17));
    expect(result.last.id, 1);
    expect(batches, 2);
  });

  test('invalid contract triggers overall single-page fallback', () async {
    var singles = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'invoke');
      final request = requestOf(call);
      if (request['method'] == 'jm_page_image_batch') {
        return envelope(jsonEncode({'version': 2, 'items': []}));
      }
      singles++;
      final params =
          jsonDecode(request['params'] as String) as Map<String, dynamic>;
      return envelope('/safe/${params['image_name']}');
    });
    final result = await methods.jmPageImageBatch([
      const JmPageImageRequest(1, 'a.jpg'),
      const JmPageImageRequest(2, 'b.jpg')
    ], enabled: true);
    expect(result, hasLength(2));
    expect(singles, 2);
    expect(result.any((x) => x.error?.contains('http') ?? false), isFalse);
  });

  test('malformed item is a contract failure and falls back all pages',
      () async {
    var batchCalls = 0;
    var singleCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'invoke');
      final request = requestOf(call);
      if (request['method'] == 'jm_page_image_batch') {
        batchCalls++;
        return envelope(jsonEncode({
          'version': 1,
          'items': [
            {'id': 1, 'path': '/safe/a'},
            'not-an-object',
          ],
        }));
      }
      singleCalls++;
      return envelope('/safe/single');
    });
    final result = await methods.jmPageImageBatch(
      [
        const JmPageImageRequest(1, 'a.jpg'),
        const JmPageImageRequest(2, 'b.jpg')
      ],
      enabled: true,
    );
    expect(batchCalls, 1);
    expect(singleCalls, 2);
    expect(result.every((item) => item.succeeded), isTrue);
  });

  test('non-string path or error is a contract failure', () async {
    var singleCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'invoke');
      final request = requestOf(call);
      if (request['method'] == 'jm_page_image_batch') {
        return envelope(jsonEncode({
          'version': 1,
          'items': [
            {'id': 1, 'path': 123},
          ],
        }));
      }
      singleCalls++;
      return envelope('/safe/single');
    });

    final result = await methods.jmPageImageBatch(
      [const JmPageImageRequest(1, 'a.jpg')],
      enabled: true,
    );
    expect(singleCalls, 1);
    expect(result.single.succeeded, isTrue);
  });
}
