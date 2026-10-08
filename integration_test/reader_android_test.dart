import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/reader_regression_test.dart' as reader_regressions;

// Run the same real-widget gesture/progress contracts on an Android engine.
// The suite injects only image/network fixtures, not gesture behavior.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var surfaceConverted = false;
  setUp(() => surfaceConverted = false);
  reader_regressions.readerCheckpoint = (name, tester) async {
    if (!surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      surfaceConverted = true;
      await tester.pump();
    }
    await binding.takeScreenshot(name);
  };
  reader_regressions.main();
}
