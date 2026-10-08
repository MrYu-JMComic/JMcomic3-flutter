import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory(
      Platform.environment['READER_TEST_OUTPUT'] ?? 'dist/device-test');
  await output.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [arguments]) async {
      // 将设备原始截图保存为 PNG，供复查手势、进度和退出后的真实画面。
      await File('${output.path}/$name.png').writeAsBytes(bytes);
      return bytes.isNotEmpty;
    },
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? {});
      // 截图已单独保存，结果文件仅保留名称和长度，避免重复写入大段二进制。
      final screenshots = report['screenshots'] as List?;
      if (screenshots != null) {
        report['screenshots'] = screenshots.map((dynamic screenshot) {
          final item = screenshot as Map;
          return {
            'name': item['screenshotName'],
            'byte_count': (item['bytes'] as List).length,
          };
        }).toList();
      }
      await writeResponseData(report,
          destinationDirectory: output.path,
          testOutputFilename: 'reader_android_report');
    },
    writeResponseOnFailure: true,
  );
}
