import 'dart:ui' as ui;

import 'package:flutter/material.dart' show ValueKey;
import 'package:flutter/rendering.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/reader_regression_test.dart' as reader_regressions;

// Run the same real-widget gesture/progress contracts on an Android engine.
// The suite injects only image/network fixtures, not gesture behavior.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  reader_regressions.readerCheckpoint = (name, tester) async {
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('reader-regression-surface')));
    // Capture the tested Flutter surface directly. Android's ImageView capture
    // can wait indefinitely for a native frame after the test resizes the view.
    await tester.runAsync(() async {
      final image = await boundary
          .toImage(pixelRatio: tester.view.devicePixelRatio)
          .timeout(const Duration(seconds: 20));
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) throw StateError('Reader screenshot is empty: $name');
        binding.reportData ??= <String, dynamic>{};
        final screenshots = binding.reportData!
            .putIfAbsent('screenshots', () => <Map<String, dynamic>>[]) as List;
        screenshots.add({
          'screenshotName': name,
          'bytes': png.buffer.asUint8List(),
        });
      } finally {
        image.dispose();
      }
    });
  };
  reader_regressions.main();
}
