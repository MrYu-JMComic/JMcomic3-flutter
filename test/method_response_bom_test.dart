import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:jmcomic3/basic/method_response_decoder.dart';
import 'package:jmcomic3/basic/methods.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('strips a BOM from the outer bridge response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return '\uFEFF${jsonEncode({
            'error_message': '',
            'response_data': 'ok',
          })}';
    });

    expect(await methods.loadProperty('key'), 'ok');
  });

  test('strips a BOM from response_data before scalar parsing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return jsonEncode({
        'error_message': '',
        'response_data': '\uFEFF3',
      });
    });

    expect(await methods.ping('index'), 3);
  });

  test('decodes a BOM-prefixed JSON object payload', () {
    final decoded = decodeMapResponse('\uFEFF{"value":1}', 'bom_object');
    expect(decoded, {'value': 1});
  });

  test('decodes a BOM-prefixed nested JSON string payload', () {
    final nested = jsonEncode('\uFEFF[{"value":1}]');
    expect(decodeListResponse(nested, 'bom_list'), [
      {'value': 1},
    ]);
  });

  test('does not strip BOM-like text after the JSON boundary', () {
    final decoded = decodeMapResponse(
      jsonEncode({'value': '\uFEFFtext'}),
      'bom_value',
    );
    expect(decoded['value'], '\uFEFFtext');
  });
}
